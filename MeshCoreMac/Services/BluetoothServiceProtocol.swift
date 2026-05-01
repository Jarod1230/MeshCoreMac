// MeshCoreMac/Services/BluetoothServiceProtocol.swift
//
// Abstraktion über CoreBluetooth, damit ViewModels gegen einen Mock testbar
// sind. Das Protokoll ist `@MainActor`-isoliert: alle Zugriffe auf
// `CBPeripheral` (das nicht Sendable ist) finden auf dem Main-Thread statt.

import CoreBluetooth
import Foundation

@MainActor
protocol BluetoothServiceProtocol: AnyObject {
    var connectionState: ConnectionState { get }
    var discoveredDevices: [CBPeripheral] { get }
    /// Rohe BLE-Frames (Node → App). ChatViewModel konsumiert diesen Stream.
    var incomingFrames: AsyncStream<Data> { get }
    /// Dekodierte Node-Ereignisse: selfInfo, nodeAdvert, contact, contactsStart/End.
    var nodeEventStream: AsyncStream<DecodedFrame> { get }

    func startScanning()
    func stopScanning()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
    func send(_ data: Data) throws
    func setLastKnownPeripheralId(_ id: UUID?)
}
