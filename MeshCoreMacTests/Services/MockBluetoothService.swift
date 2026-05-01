// MeshCoreMacTests/Services/MockBluetoothService.swift
//
// In-Memory-Mock für `BluetoothServiceProtocol`. ViewModel-Tests können
// `simulateIncomingFrame(_:)` nutzen, um BLE-Empfang zu simulieren, oder
// `sentFrames` inspizieren, um ausgehende Frames zu verifizieren.

import CoreBluetooth
import Foundation
@testable import MeshCoreMac

@Observable
@MainActor
final class MockBluetoothService: BluetoothServiceProtocol {
    var connectionState: ConnectionState = .disconnected
    var discoveredDevices: [CBPeripheral] = []
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation
    let nodeEventStream: AsyncStream<DecodedFrame>
    private let nodeEventContinuation: AsyncStream<DecodedFrame>.Continuation

    var sentFrames: [Data] = []
    var scanStarted = false
    var disconnectCalled = false

    init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
        let (nodeStream, nodeCont) = AsyncStream<DecodedFrame>.makeStream()
        self.nodeEventStream = nodeStream
        self.nodeEventContinuation = nodeCont
    }

    func startScanning() { scanStarted = true }
    func stopScanning() { scanStarted = false }

    func connect(to peripheral: CBPeripheral) {
        connectionState = .ready(peripheralName: peripheral.name ?? "Mock-Node")
    }

    func disconnect() {
        disconnectCalled = true
        connectionState = .disconnected
    }

    func send(_ data: Data) throws { sentFrames.append(data) }
    func setLastKnownPeripheralId(_ id: UUID?) {}

    // MARK: - Test-Helpers

    func simulateIncomingFrame(_ data: Data) {
        frameContinuation.yield(data)
    }

    func simulateNodeEvent(_ frame: DecodedFrame) {
        nodeEventContinuation.yield(frame)
    }

    func simulateDisconnect() {
        connectionState = .failed(peripheralName: "Mock-Node", error: "Verbindung verloren")
    }

    func simulateConnect(peripheralName: String = "Mock-Node") {
        connectionState = .ready(peripheralName: peripheralName)
    }

    deinit {
        frameContinuation.finish()
        nodeEventContinuation.finish()
    }
}
