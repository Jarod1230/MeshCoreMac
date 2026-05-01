import XCTest
@testable import MeshCoreMac

@MainActor
final class ConnectionViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var vm: ConnectionViewModel!

    override func setUp() {
        mockBluetooth = MockBluetoothService()
        vm = ConnectionViewModel(bluetoothService: mockBluetooth)
    }

    func testInitialState_isDisconnected() {
        XCTAssertEqual(vm.connectionState, .disconnected)
        XCTAssertFalse(vm.isConnected)
    }

    func testStartScan_callsServiceStartScanning() {
        vm.startScan()
        XCTAssertTrue(mockBluetooth.scanStarted)
    }

    func testDisconnect_callsServiceDisconnect() {
        vm.disconnect()
        XCTAssertTrue(mockBluetooth.disconnectCalled)
    }
}
