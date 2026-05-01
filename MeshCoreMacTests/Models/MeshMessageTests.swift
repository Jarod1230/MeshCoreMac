import XCTest
@testable import MeshCoreMac

final class MeshMessageTests: XCTestCase {

    func testChannelMessage_hasChannelIndex_noContactId() throws {
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Node-42",
            text: "Hallo Mesh",
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: 2, snr: -8.5, routeDisplay: "via R-7"),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        guard case .channel(let idx) = msg.kind else {
            return XCTFail("Expected channel message")
        }
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(msg.routing?.hops, 2)
        let snr = try XCTUnwrap(msg.routing?.snr)
        XCTAssertEqual(snr, -8.5, accuracy: 0.001)
        XCTAssertEqual(msg.routing?.routeDisplay, "via R-7")
    }

    func testDirectMessage_hasContactId_noChannelIndex() {
        let msg = MeshMessage(
            id: UUID(),
            kind: .direct(contactId: "abc123"),
            senderName: "Node-42",
            text: "Privat",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sent,
            isIncoming: false
        )
        guard case .direct(let cid) = msg.kind else {
            return XCTFail("Expected direct message")
        }
        XCTAssertEqual(cid, "abc123")
    }

    func testDeliveryStatus_transitions() {
        var msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Me",
            text: "Test",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sending,
            isIncoming: false
        )
        XCTAssertEqual(msg.deliveryStatus, .sending)
        msg.deliveryStatus = .delivered
        XCTAssertEqual(msg.deliveryStatus, .delivered)
    }

    func testConnectionState_displayName_ready() {
        let state = ConnectionState.ready(peripheralName: "Node-42")
        XCTAssertEqual(state.displayName, "Bereit: Node-42")
        XCTAssertTrue(state.isReady)
    }

    func testConnectionState_displayName_disconnected() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isReady)
    }
}
