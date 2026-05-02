// MeshCoreMac/Services/MeshCoreBluetoothService.swift
//
// CoreBluetooth-basierter BLE-Service für MeshCore-Companion-Nodes.
//
// - `@MainActor`-isoliert: alle CB-Zugriffe laufen auf dem Main-Thread.
//   `CBCentralManager(delegate: self, queue: .main)` stellt das sicher.
// - Delegate-Methoden nutzen `@preconcurrency`-Konformanz: CoreBluetooth-
//   Delegate-Protokolle sind noch nicht mit `Sendable` annotiert. Da CB
//   alle Callbacks garantiert auf der bei init übergebenen Queue (.main)
//   ausführt, unterdrückt `@preconcurrency` die Swift-6-Warnungen legal.
// - `incomingFrames` ist ein `AsyncStream<Data>`: Konsumenten (z. B. ein
//   ViewModel) iterieren asynchron, ohne ein eigenes Delegate zu brauchen.
// - Auto-Reconnect: Bei Disconnect/Failure wird alle 10 s versucht,
//   den letzten bekannten Peripheral wiederherzustellen.

import CoreBluetooth
import Foundation
import Observation

@Observable
@MainActor
final class MeshCoreBluetoothService: NSObject, BluetoothServiceProtocol {

    // MARK: - Observierter Zustand
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredDevices: [CBPeripheral] = []

    // MARK: - Async Frame Stream
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation
    let nodeEventStream: AsyncStream<DecodedFrame>
    private let nodeEventContinuation: AsyncStream<DecodedFrame>.Continuation
    let rxLogStream: AsyncStream<RxLogEntry>
    private let rxLogContinuation: AsyncStream<RxLogEntry>.Continuation

    // MARK: - CoreBluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    // MARK: - Reconnect
    private var lastKnownPeripheralId: UUID?
    nonisolated(unsafe) private var reconnectTask: Task<Void, Never>?

    // MARK: - Konstanten
    private static let lastPeripheralIdKey = "lastPeripheralId"

    // MARK: - Init

    override init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
        let (nodeStream, nodeCont) = AsyncStream<DecodedFrame>.makeStream()
        self.nodeEventStream = nodeStream
        self.nodeEventContinuation = nodeCont
        let (logStream, logCont) = AsyncStream<RxLogEntry>.makeStream()
        self.rxLogStream = logStream
        self.rxLogContinuation = logCont
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        reconnectTask?.cancel()
        frameContinuation.finish()
        nodeEventContinuation.finish()
        rxLogContinuation.finish()
    }

    // MARK: - Public API

    func setLastKnownPeripheralId(_ id: UUID?) {
        self.lastKnownPeripheralId = id
        UserDefaults.standard.set(id?.uuidString, forKey: Self.lastPeripheralIdKey)
    }

    func startScanning() {
        discoveredDevices = []
        guard centralManager.state == .poweredOn else { return }
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [MeshCoreProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connecting(peripheralName: peripheral.name ?? "Node")
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        reconnectTask?.cancel()
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        connectionState = .disconnected
    }

    func send(_ data: Data) throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = txCharacteristic else {
            throw BluetoothError.notConnected
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        rxLogContinuation.yield(RxLogEntry(
            id: UUID(),
            timestamp: Date(),
            direction: .outgoing,
            rawBytes: data,
            decoded: nil
        ))
    }

    // MARK: - Auto-Reconnect

    private func scheduleReconnect(peripheralName: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                self?.attemptReconnect(peripheralName: peripheralName)
            }
        }
    }

    private func attemptReconnect(peripheralName: String) {
        guard let id = lastKnownPeripheralId else {
            startScanning()
            return
        }
        let known = centralManager.retrievePeripherals(withIdentifiers: [id])
        if let peripheral = known.first {
            connect(to: peripheral)
        } else {
            startScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate
//
// `@preconcurrency`-Konformanz: Apple hat die Delegate-Protokolle (Stand
// 2026) noch nicht mit `Sendable`-Annotationen versehen. CoreBluetooth ruft
// die Methoden aber garantiert auf der bei `init` übergebenen Queue auf
// (`.main`). Mit `@preconcurrency` blendet Swift 6 die strict-concurrency-
// Checks für die nicht-Sendable Parameter (`CBPeripheral`, `CBService`,
// `CBCharacteristic`) gezielt aus.

extension MeshCoreBluetoothService: @preconcurrency CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let idStr = UserDefaults.standard.string(forKey: Self.lastPeripheralIdKey),
               let id = UUID(uuidString: idStr) {
                lastKnownPeripheralId = id
            }
            attemptReconnect(peripheralName: "")
        case .poweredOff:
            connectionState = .failed(peripheralName: "", error: "Bluetooth ausgeschaltet")
        case .unauthorized:
            connectionState = .failed(peripheralName: "", error: "Bluetooth-Berechtigung fehlt")
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
        }
        if peripheral.identifier == lastKnownPeripheralId {
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected(peripheralName: peripheral.name ?? "Node")
        peripheral.delegate = self
        peripheral.discoverServices([MeshCoreProtocol.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let name = peripheral.name ?? "Node"
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        connectionState = .failed(
            peripheralName: name,
            error: error?.localizedDescription ?? "Verbindung getrennt"
        )
        scheduleReconnect(peripheralName: name)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let name = peripheral.name ?? "Node"
        connectionState = .failed(
            peripheralName: name,
            error: error?.localizedDescription ?? "Verbindungsaufbau fehlgeschlagen"
        )
        scheduleReconnect(peripheralName: name)
    }
}

// MARK: - CBPeripheralDelegate

extension MeshCoreBluetoothService: @preconcurrency CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == MeshCoreProtocol.serviceUUID {
            peripheral.discoverCharacteristics(
                [MeshCoreProtocol.txCharUUID, MeshCoreProtocol.rxCharUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == MeshCoreProtocol.txCharUUID {
                txCharacteristic = char
            } else if char.uuid == MeshCoreProtocol.rxCharUUID {
                rxCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        if txCharacteristic != nil && rxCharacteristic != nil {
            connectionState = .ready(peripheralName: peripheral.name ?? "Node")
            setLastKnownPeripheralId(peripheral.identifier)
            sendInitSequence()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        frameContinuation.yield(value)

        let decoded = try? MeshCoreProtocolService.decodeFrame(value)

        if let decoded {
            switch decoded {
            case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd,
                 .battAndStorage, .noiseFloor:
                nodeEventContinuation.yield(decoded)
            case .newChannelMessage, .newDirectMessage, .messageAck:
                break
            }
        }

        rxLogContinuation.yield(RxLogEntry(
            id: UUID(),
            timestamp: Date(),
            direction: .incoming,
            rawBytes: value,
            decoded: decoded?.displayDescription
                ?? value.first.map { "Unbekannt: 0x\(String(format: "%02X", $0))" }
        ))
    }

    private func sendInitSequence() {
        try? send(MeshCoreProtocolService.encodeAppStart())
        try? send(MeshCoreProtocolService.encodeDeviceQuery())
        try? send(MeshCoreProtocolService.encodeGetContacts())
    }
}

// MARK: - Fehler

enum BluetoothError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Kein verbundener Node"
        }
    }
}
