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
        XCTAssertEqual(msg.routing?.snr ?? 0, -8.0, accuracy: 1.0)
        guard case .channel(let idx) = msg.kind else { return XCTFail() }
        XCTAssertEqual(idx, 0)
    }

    func testDecodeUnknownFrame_throwsError() {
        let frame = Data([0xFF, 0x00])
        XCTAssertThrowsError(try MeshCoreProtocolService.decodeFrame(frame))
    }

    func testEncodeGetContacts_hasSingleCommandByte() {
        let frame = MeshCoreProtocolService.encodeGetContacts()
        XCTAssertFalse(frame.isEmpty)
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.getContacts.rawValue)
    }

    func testDecodeSelfInfo_parsesNodeIdAndPosition() throws {
        // SELF_INFO payload: [pubkey:32][ts:4][lat_f32_le:4][lon_f32_le:4][alt:4][name]
        var bytes = [UInt8](repeating: 0xAA, count: 32) // pubkey — first 4 bytes become nodeId
        bytes += [0x00, 0x00, 0x00, 0x00]               // timestamp
        // lat = 48.137  → Float32 little-endian
        let latFloat = Float(48.137)
        let latBits = latFloat.bitPattern
        bytes += [UInt8(latBits & 0xFF), UInt8((latBits >> 8) & 0xFF),
                  UInt8((latBits >> 16) & 0xFF), UInt8((latBits >> 24) & 0xFF)]
        // lon = 11.575
        let lonFloat = Float(11.575)
        let lonBits = lonFloat.bitPattern
        bytes += [UInt8(lonBits & 0xFF), UInt8((lonBits >> 8) & 0xFF),
                  UInt8((lonBits >> 16) & 0xFF), UInt8((lonBits >> 24) & 0xFF)]
        bytes += [0x00, 0x00, 0x00, 0x00]               // alt
        bytes += Array("MyNode".utf8)
        var frame = [MeshCoreProtocol.Response.selfInfo.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .selfInfo(let nodeId, let lat, let lon, let firmware) = decoded else {
            return XCTFail("Expected .selfInfo, got \(decoded)")
        }
        XCTAssertEqual(nodeId, "aaaaaaaa")
        XCTAssertEqual(lat ?? 0, 48.137, accuracy: 0.01)
        XCTAssertEqual(lon ?? 0, 11.575, accuracy: 0.01)
        XCTAssertEqual(firmware, "MyNode")
    }

    func testDecodeAdvert_parsesContactIdAndPosition() throws {
        // ADVERT payload same format as SELF_INFO
        var bytes = [UInt8](repeating: 0xBB, count: 32) // pubkey
        bytes += [0x00, 0x00, 0x00, 0x00]               // timestamp
        let latFloat = Float(52.52)
        let latBits = latFloat.bitPattern
        bytes += [UInt8(latBits & 0xFF), UInt8((latBits >> 8) & 0xFF),
                  UInt8((latBits >> 16) & 0xFF), UInt8((latBits >> 24) & 0xFF)]
        let lonFloat = Float(13.405)
        let lonBits = lonFloat.bitPattern
        bytes += [UInt8(lonBits & 0xFF), UInt8((lonBits >> 8) & 0xFF),
                  UInt8((lonBits >> 16) & 0xFF), UInt8((lonBits >> 24) & 0xFF)]
        bytes += [0x00, 0x00, 0x00, 0x00]               // alt
        bytes += Array("Berlin".utf8) + [0x00]          // NUL-terminated name
        var frame = [MeshCoreProtocol.Push.advert.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .nodeAdvert(let contactId, let name, let lat, let lon) = decoded else {
            return XCTFail("Expected .nodeAdvert, got \(decoded)")
        }
        XCTAssertEqual(contactId, "bbbbbbbb")
        XCTAssertEqual(name, "Berlin")
        XCTAssertEqual(lat ?? 0, 52.52, accuracy: 0.01)
        XCTAssertEqual(lon ?? 0, 13.405, accuracy: 0.01)
    }

    func testDecodeContact_parsesNameAndOnlineFlag() throws {
        // CONTACT payload: [pubkey:32][last_heard:4][flags:1][name:variable]
        var bytes = [UInt8](repeating: 0xCC, count: 32) // pubkey
        bytes += [0x00, 0x00, 0x00, 0x00]               // last_heard
        bytes += [0x01]                                  // flags: bit0 = online
        bytes += Array("Charlie".utf8)
        var frame = [MeshCoreProtocol.Response.contact.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .contact(let c) = decoded else {
            return XCTFail("Expected .contact, got \(decoded)")
        }
        XCTAssertEqual(c.id, "cccccccc")
        XCTAssertEqual(c.name, "Charlie")
        XCTAssertTrue(c.isOnline)
    }

    func testDecodeContactsEnd_returnsContactsEnd() throws {
        let frame = Data([MeshCoreProtocol.Response.endOfContacts.rawValue])
        let decoded = try MeshCoreProtocolService.decodeFrame(frame)
        XCTAssertEqual(decoded, .contactsEnd)
    }

    func testDecodeContactsStart_returnsContactsStart() throws {
        let frame = Data([MeshCoreProtocol.Response.contactsStart.rawValue])
        let decoded = try MeshCoreProtocolService.decodeFrame(frame)
        XCTAssertEqual(decoded, .contactsStart)
    }
}
