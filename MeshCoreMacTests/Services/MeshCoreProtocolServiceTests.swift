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

    func testEncodeChannelMessage_correctFormat() throws {
        let text = "Hallo Mesh"
        let frame = try MeshCoreProtocolService.encodeSendTextMessage(
            text: text, channelIndex: 1, recipientId: nil
        )
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.sendChannelTxtMsg.rawValue)
        XCTAssertEqual(frame[1], 0x00)
        XCTAssertEqual(frame[2], 0x01)
        let msgData = Data(frame.dropFirst(7))
        XCTAssertEqual(String(data: msgData, encoding: .utf8), text)
    }

    func testEncodeSendTextMessage_throwsOnOverlongText() {
        let longText = String(repeating: "A", count: 134) // > 133 Zeichen
        XCTAssertThrowsError(
            try MeshCoreProtocolService.encodeSendTextMessage(
                text: longText, channelIndex: 0, recipientId: nil
            )
        )
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
        var bytes: [UInt8] = [0x01, 0x14, 0x14]
        bytes += [UInt8](repeating: 0xAA, count: 32)
        let lat_i32 = Int32(48.137 * 1_000_000)
        bytes += [UInt8(lat_i32 & 0xFF), UInt8((lat_i32 >> 8) & 0xFF),
                  UInt8((lat_i32 >> 16) & 0xFF), UInt8((lat_i32 >> 24) & 0xFF)]
        let lon_i32 = Int32(11.575 * 1_000_000)
        bytes += [UInt8(lon_i32 & 0xFF), UInt8((lon_i32 >> 8) & 0xFF),
                  UInt8((lon_i32 >> 16) & 0xFF), UInt8((lon_i32 >> 24) & 0xFF)]
        bytes += [UInt8](repeating: 0x00, count: 14)
        bytes += Array("MyNode".utf8)
        var frame = [MeshCoreProtocol.Response.selfInfo.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .selfInfo(let nodeId, let lat, let lon, let firmware, _, _, _, _) = decoded else {
            return XCTFail("Expected .selfInfo, got \(decoded)")
        }
        XCTAssertEqual(nodeId, "aaaaaaaa")
        XCTAssertEqual(lat ?? 0, 48.137, accuracy: 0.001)
        XCTAssertEqual(lon ?? 0, 11.575, accuracy: 0.001)
        XCTAssertEqual(firmware, "MyNode")
    }

    func testDecodeAdvert_parsesContactIdAndName() throws {
        var bytes = [UInt8](repeating: 0xBB, count: 32)
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += [UInt8](repeating: 0x00, count: 64)
        bytes += [0x90]  // flags: 0x10 (lat/lon) | 0x80 (name)
        let lat_i32 = Int32(52.52 * 1_000_000)
        bytes += [UInt8(lat_i32 & 0xFF), UInt8((lat_i32 >> 8) & 0xFF),
                  UInt8((lat_i32 >> 16) & 0xFF), UInt8((lat_i32 >> 24) & 0xFF)]
        let lon_i32 = Int32(13.405 * 1_000_000)
        bytes += [UInt8(lon_i32 & 0xFF), UInt8((lon_i32 >> 8) & 0xFF),
                  UInt8((lon_i32 >> 16) & 0xFF), UInt8((lon_i32 >> 24) & 0xFF)]
        bytes += Array("Berlin".utf8) + [0x00]
        var frame = [MeshCoreProtocol.Push.advert.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .nodeAdvert(let contactId, let name, let lat, let lon) = decoded else {
            return XCTFail("Expected .nodeAdvert, got \(decoded)")
        }
        XCTAssertEqual(contactId, "bbbbbbbb")
        XCTAssertEqual(name, "Berlin")
        XCTAssertEqual(lat ?? 0, 52.52, accuracy: 0.001)
        XCTAssertEqual(lon ?? 0, 13.405, accuracy: 0.001)
    }

    func testDecodeDeviceInfo_parsesCorrectly() throws {
        var bytes: [UInt8] = [0x05, 0x19, 0x08]
        bytes += [0x00, 0x00, 0x00, 0x00]
        var build = Array("build-abc".utf8); while build.count < 12 { build.append(0) }
        var model = Array("RepeatStar".utf8); while model.count < 40 { model.append(0) }
        var version = Array("1.2.3".utf8); while version.count < 20 { version.append(0) }
        bytes += build + model + version
        var frame = [MeshCoreProtocol.Response.deviceInfo.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .deviceInfo(let info) = decoded else {
            return XCTFail("Expected .deviceInfo, got \(decoded)")
        }
        XCTAssertEqual(info.firmwareVersion, 5)
        XCTAssertEqual(info.maxContacts, 50)
        XCTAssertEqual(info.maxChannels, 8)
        XCTAssertEqual(info.firmwareBuild, "build-abc")
        XCTAssertEqual(info.model, "RepeatStar")
        XCTAssertEqual(info.version, "1.2.3")
    }

    func testDecodeBattAndStorage_valid() throws {
        var frame = Data([MeshCoreProtocol.Response.battAndStorage.rawValue])
        frame.append(contentsOf: [0x70, 0x0E])       // 0x0E70 = 3696mV
        frame.append(contentsOf: [0x00, 0x10, 0x00, 0x00])  // 4096 KB
        frame.append(contentsOf: [0x00, 0x20, 0x00, 0x00])  // 8192 KB
        let decoded = try MeshCoreProtocolService.decodeFrame(frame)
        guard case .battAndStorage(let mv, let used, let total) = decoded else {
            XCTFail("Expected .battAndStorage"); return
        }
        XCTAssertEqual(mv, 3696)
        XCTAssertEqual(used, 4096)
        XCTAssertEqual(total, 8192)
    }

    func testDecodeChannelMessage_parsesCorrectly() throws {
        var bytes: [UInt8] = [0x01, 0x02, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += Array("Hello".utf8)
        var frame = [MeshCoreProtocol.Response.channelMsgRecv.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .newChannelMessage(let msg) = decoded else {
            return XCTFail("Expected .newChannelMessage")
        }
        XCTAssertEqual(msg.text, "Hello")
        XCTAssertEqual(msg.routing?.hops, 2)
        guard case .channel(let idx) = msg.kind else { return XCTFail() }
        XCTAssertEqual(idx, 1)
    }

    func testDecodeChannelMessageV3_includesSNR() throws {
        let snrRaw = Int8(-12)
        var bytes: [UInt8] = [UInt8(bitPattern: snrRaw), 0x00, 0x00, 0x00, 0x01, 0x00]
        bytes += [0x00, 0x00, 0x00, 0x00]
        bytes += Array("V3".utf8)
        var frame = [MeshCoreProtocol.ResponseV3.channelMsgRecvV3.rawValue]
        frame += bytes
        let decoded = try MeshCoreProtocolService.decodeFrame(Data(frame))
        guard case .newChannelMessage(let msg) = decoded else {
            return XCTFail("Expected .newChannelMessage")
        }
        XCTAssertEqual(msg.text, "V3")
        XCTAssertEqual(msg.routing?.snr ?? 0, -3.0, accuracy: 0.01)
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

    func testDecodeNoiseFloor_valid() throws {
        var frame = Data([MeshCoreProtocol.Push.statusResponse.rawValue])
        frame.append(UInt8(bitPattern: Int8(-80)))
        frame.append(UInt8(bitPattern: Int8(-110)))
        let decoded = try MeshCoreProtocolService.decodeFrame(frame)
        guard case .noiseFloor(let rssi, let noise) = decoded else {
            XCTFail("Expected .noiseFloor"); return
        }
        XCTAssertEqual(rssi, -80)
        XCTAssertEqual(noise, -110)
    }

    func testEncodeTracePath_producesCorrectBytes() {
        let data = MeshCoreProtocolService.encodeTracePath(contactId: "a1b2c3d4")
        XCTAssertEqual(data[0], MeshCoreProtocol.Command.tracePath.rawValue)
        XCTAssertEqual(data.count, 5)
        XCTAssertEqual(data[1], 0xa1)
        XCTAssertEqual(data[2], 0xb2)
        XCTAssertEqual(data[3], 0xc3)
        XCTAssertEqual(data[4], 0xd4)
    }
}
