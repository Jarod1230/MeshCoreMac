// MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift
import XCTest
@testable import MeshCoreMac

final class MeshCoreProtocolServiceTests: XCTestCase {

    func testEncodeAppStart_hasSingleCommandByte() {
        let frame = MeshCoreProtocolService.encodeAppStart()
        XCTAssertFalse(frame.isEmpty)
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.appStart.rawValue)
    }

    func testEncodeDeviceQuery_hasSingleCommandByte() {
        let frame = MeshCoreProtocolService.encodeDeviceQuery()
        XCTAssertFalse(frame.isEmpty)
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.deviceQuery.rawValue)
    }

    func testEncodeSendTextMessage_containsText() throws {
        let text = "Hallo Mesh"
        let channelIndex: UInt8 = 0
        let frame = try MeshCoreProtocolService.encodeSendTextMessage(
            text: text, channelIndex: channelIndex, recipientId: nil
        )
        XCTAssertGreaterThan(frame.count, 2)
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.sendTxtMsg.rawValue)
        // Text-Payload nach Command-Byte und Channel-Byte
        let textData = Data(frame.dropFirst(2))
        XCTAssertEqual(String(data: textData, encoding: .utf8), text)
    }

    func testEncodeSendTextMessage_throwsOnOverlongText() {
        let longText = String(repeating: "A", count: 134) // > 133 Zeichen
        XCTAssertThrowsError(
            try MeshCoreProtocolService.encodeSendTextMessage(
                text: longText, channelIndex: 0, recipientId: nil
            )
        )
    }

    func testDecodeNewMessage_parsesCorrectly() throws {
        // Synthetischer NEW_MSG-Frame: [CMD][channelIdx][hops][snr_raw][utf8_text]
        var frameBytes: [UInt8] = [
            MeshCoreProtocol.Response.newMsg.rawValue,
            0x00,   // channelIndex = 0
            0x02,   // hops = 2
            0xF8,   // snr raw byte (signed: -8)
        ]
        frameBytes += Array("Hallo".utf8)
        let frame = Data(frameBytes)

        let decoded = try MeshCoreProtocolService.decodeFrame(frame)
        guard case .newChannelMessage(let msg) = decoded else {
            return XCTFail("Expected newChannelMessage, got \(decoded)")
        }
        XCTAssertEqual(msg.text, "Hallo")
        XCTAssertEqual(msg.routing?.hops, 2)
        guard case .channel(let idx) = msg.kind else { return XCTFail() }
        XCTAssertEqual(idx, 0)
    }

    func testDecodeUnknownFrame_throwsError() {
        let frame = Data([0xFF, 0x00])
        XCTAssertThrowsError(try MeshCoreProtocolService.decodeFrame(frame))
    }
}
