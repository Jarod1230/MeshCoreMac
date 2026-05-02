import XCTest
@testable import MeshCoreMac

@MainActor
final class ChatViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var store: MessageStore!
    var vm: ChatViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        store = try MessageStore(inMemory: true)
        vm = ChatViewModel(
            bluetoothService: mockBluetooth,
            messageStore: store,
            conversation: .channel(index: 0),
            notificationService: NotificationService()
        )
    }

    func testSendMessage_encodesAndSendsFrame() async throws {
        try await vm.send(text: "Hallo")
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        let frame = mockBluetooth.sentFrames[0]
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.sendChannelTxtMsg.rawValue)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame[2], 0x00)
    }

    func testSendMessage_savesToStore() async throws {
        try await vm.send(text: "Hallo")
        let msgs = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "Hallo")
        XCTAssertEqual(msgs[0].deliveryStatus, .sending)
    }

    func testSendMessage_rejectsOverlongText() async throws {
        let longText = String(repeating: "A", count: MeshCoreProtocol.maxMessageLength + 1)
        do {
            try await vm.send(text: longText)
            XCTFail("Hätte Fehler werfen sollen")
        } catch ProtocolError.messageTooLong {
            // erwartet
        }
    }

    func testIncomingFrame_appearsInMessages() async throws {
        await vm.loadMessages()
        var frameBytes: [UInt8] = [
            MeshCoreProtocol.Response.channelMsgRecv.rawValue,
            0x00, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x00
        ]
        frameBytes += Array("Incoming".utf8)
        mockBluetooth.simulateIncomingFrame(Data(frameBytes))
        for _ in 0..<20 {
            await Task.yield()
            if !vm.messages.isEmpty { break }
        }
        XCTAssertFalse(vm.messages.isEmpty)
        XCTAssertEqual(vm.messages.first?.text, "Incoming")
    }
}
