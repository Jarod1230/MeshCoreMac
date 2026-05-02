// MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift
import XCTest
@testable import MeshCoreMac

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var vm: DiagnosticsViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        vm = DiagnosticsViewModel(bluetoothService: mockBluetooth)
        await vm.start()
    }

    override func tearDown() async throws {
        vm = nil
        mockBluetooth = nil
    }

    func testLogEntries_appendOnIncomingEntry() async throws {
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: Data([0x04]), decoded: "GET_CONTACTS")
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { !self.vm.logEntries.isEmpty }
        XCTAssertEqual(vm.logEntries.count, 1)
        XCTAssertEqual(vm.logEntries[0].decoded, "GET_CONTACTS")
    }

    func testLogEntries_cappedAt200() async throws {
        for i in 0..<210 {
            let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                                   direction: .incoming,
                                   rawBytes: Data([UInt8(i % 256)]),
                                   decoded: "Entry \(i)")
            mockBluetooth.simulateRxLogEntry(entry)
        }
        try await waitUntil { self.vm.logEntries.count >= 200 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertLessThanOrEqual(vm.logEntries.count, DiagnosticsViewModel.maxEntries)
    }

    func testSendCLICommand_validHex_sendsBytes() async throws {
        vm.cliInput = "04"
        try await vm.sendCLICommand()
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        XCTAssertEqual(mockBluetooth.sentFrames[0], Data([0x04]))
    }

    func testSendCLICommand_multiByteHex_sendsCorrectBytes() async throws {
        vm.cliInput = "07 A1 B2 C3"
        try await vm.sendCLICommand()
        XCTAssertEqual(mockBluetooth.sentFrames[0], Data([0x07, 0xA1, 0xB2, 0xC3]))
    }

    func testSendCLICommand_invalidHex_throws() async throws {
        vm.cliInput = "ZZ"
        do {
            try await vm.sendCLICommand()
            XCTFail("Hätte CLIError werfen sollen")
        } catch DiagnosticsViewModel.CLIError.invalidHex(let token) {
            XCTAssertEqual(token, "ZZ")
        }
    }

    func testSendCLICommand_addsToHistory() async throws {
        vm.cliInput = "04"
        try await vm.sendCLICommand()
        XCTAssertEqual(vm.cliHistory.first, "04")
        XCTAssertEqual(vm.cliInput, "")
    }

    func testHandleEntry_battAndStorage_updatesBatteryPercent() async throws {
        var frame = Data([MeshCoreProtocol.Response.battAndStorage.rawValue])
        frame.append(80)
        frame.append(contentsOf: [0x00, 0x10, 0x00, 0x00])
        frame.append(contentsOf: [0x00, 0x40, 0x00, 0x00])
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: frame, decoded: nil)
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { self.vm.batteryPercent != nil }
        XCTAssertEqual(vm.batteryPercent, 80)
        XCTAssertEqual(vm.storageUsed, 4096)
        XCTAssertEqual(vm.storageFree, 16384)
    }

    func testHandleEntry_noiseFloor_updatesNoiseFloor() async throws {
        var frame = Data([MeshCoreProtocol.Push.statusResponse.rawValue])
        frame.append(UInt8(bitPattern: Int8(-85)))
        frame.append(UInt8(bitPattern: Int8(-115)))
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: frame, decoded: nil)
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { self.vm.noiseFloor != nil }
        XCTAssertEqual(vm.rssi, -85)
        XCTAssertEqual(vm.noiseFloor, -115)
    }

    func testRequestNodeStatus_sendsBattAndStorageCommand() async throws {
        try await vm.requestNodeStatus()
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        XCTAssertEqual(mockBluetooth.sentFrames[0][0],
                       MeshCoreProtocol.Command.getBattAndStorage.rawValue)
    }

    func testStart_calledTwice_isNoOp() async throws {
        let mockB = MockBluetoothService()
        let vm2 = DiagnosticsViewModel(bluetoothService: mockB)
        await vm2.start()
        await vm2.start()
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: Data([0x05]), decoded: "SELF_INFO")
        mockB.simulateRxLogEntry(entry)
        try await waitUntil { !vm2.logEntries.isEmpty }
        XCTAssertEqual(vm2.logEntries.count, 1)
    }

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timeout"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
