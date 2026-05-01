// MeshCoreMac/ViewModels/ConnectionViewModel.swift
import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
final class ConnectionViewModel {
    private let bluetoothService: any BluetoothServiceProtocol

    var connectionState: ConnectionState { bluetoothService.connectionState }
    var discoveredDevices: [CBPeripheral] { bluetoothService.discoveredDevices }

    var isConnected: Bool { connectionState.isConnectedOrReady }
    var errorMessage: String? = nil

    init(bluetoothService: any BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
    }

    func startScan() {
        bluetoothService.startScanning()
    }

    func connect(to peripheral: CBPeripheral) {
        bluetoothService.connect(to: peripheral)
    }

    func disconnect() {
        bluetoothService.disconnect()
    }
}
