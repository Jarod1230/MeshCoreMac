// MeshCoreMac/Services/MeshCoreProtocolService.swift
//
// Encode/Decode für das MeshCore Companion-BLE-Protokoll.
// Quelle: https://docs.meshcore.io/companion_protocol/
//
// Frame-Formate:
//   SELF_INFO/ADVERT payload: [pubkey:32][ts:4][lat_f32_le:4][lon_f32_le:4][alt_f32_le:4][name:variable]
//   CONTACT payload:          [pubkey:32][last_heard:4][flags:1][name:variable]
// VERIFY: Bei neuer Firmware-Version gegen reale Frames abgleichen.

import Foundation

enum MeshCoreProtocolService {

    // MARK: - Encoder

    static func encodeAppStart() -> Data {
        Data([MeshCoreProtocol.Command.appStart.rawValue])
    }

    static func encodeDeviceQuery() -> Data {
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue])
    }

    static func encodeGetContacts() -> Data {
        Data([MeshCoreProtocol.Command.getContacts.rawValue])
    }

    static func encodeSendTextMessage(
        text: String,
        channelIndex: UInt8,
        recipientId: String?
    ) throws -> Data {
        guard let textData = text.data(using: .utf8) else {
            throw ProtocolError.invalidPayload("Text nicht als UTF-8 kodierbar")
        }
        guard textData.count <= MeshCoreProtocol.maxMessageLength else {
            throw ProtocolError.messageTooLong(textData.count)
        }
        var frame = Data([MeshCoreProtocol.Command.sendTxtMsg.rawValue, channelIndex])
        frame.append(textData)
        return frame
    }

    // MARK: - Decoder

    static func decodeFrame(_ data: Data) throws -> DecodedFrame {
        guard !data.isEmpty else { throw ProtocolError.emptyFrame }

        let commandByte = data[data.startIndex]
        let payload = data.dropFirst()

        if let response = MeshCoreProtocol.Response(rawValue: commandByte) {
            switch response {
            case .selfInfo, .deviceInfo:
                return try decodeNodeInfo(payload)
            case .channelMsgRecv:
                return try decodeChannelMessage(payload)
            case .contactMsgRecv:
                return try decodeContactMessage(payload)
            case .sent:
                return try decodeMsgAck(payload)
            case .contactsStart:
                return .contactsStart
            case .contact:
                return try decodeContact(payload)
            case .endOfContacts:
                return .contactsEnd
            case .ok, .err, .currTime, .noMoreMessages, .battAndStorage:
                throw ProtocolError.unknownCommand(commandByte)
            }
        }

        if let push = MeshCoreProtocol.Push(rawValue: commandByte) {
            switch push {
            case .sendConfirmed:
                return try decodeMsgAck(payload)
            case .advert, .pathUpdated:
                return try decodeAdvertOrSelfInfo(payload)
            case .msgWaiting, .rawData, .loginSuccess, .loginFail, .statusResponse:
                throw ProtocolError.unknownCommand(commandByte)
            }
        }

        throw ProtocolError.unknownCommand(commandByte)
    }

    // MARK: - Private Decode Helpers

    /// Dekodiert SELF_INFO (0x05) und DEVICE_INFO (0x0D) Responses.
    /// Format: [pubkey:32][ts:4][lat_f32_le:4][lon_f32_le:4][alt_f32_le:4][name:variable]
    private static func decodeNodeInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 4 else {
            throw ProtocolError.invalidPayload("NODE_INFO payload zu kurz")
        }
        let nodeId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        if bytes.count >= 48 {
            let lat = readFloat32LE(bytes, offset: 36).map(Double.init)
            let lon = readFloat32LE(bytes, offset: 40).map(Double.init)
            let hasPosition = lat != 0.0 || lon != 0.0
            let rawName = Data(bytes.dropFirst(48))
            let nameEnd = rawName.firstIndex(of: 0) ?? rawName.endIndex
            let firmware = String(data: rawName[rawName.startIndex..<nameEnd], encoding: .utf8) ?? "unbekannt"
            return .selfInfo(
                nodeId: nodeId,
                lat: hasPosition ? lat : nil,
                lon: hasPosition ? lon : nil,
                firmware: firmware
            )
        }
        // Fallback für kurze Frames ohne Positions-Payload
        let firmware = String(data: Data(bytes.dropFirst(4)), encoding: .utf8) ?? "unbekannt"
        return .selfInfo(nodeId: nodeId, lat: nil, lon: nil, firmware: firmware)
    }

    /// Dekodiert ADVERT (0x80) und PATH_UPDATED (0x81) Push-Notifications.
    /// Format: [pubkey:32][ts:4][lat_f32_le:4][lon_f32_le:4][alt_f32_le:4][name:variable]
    private static func decodeAdvertOrSelfInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 4 else {
            throw ProtocolError.invalidPayload("ADVERT payload zu kurz")
        }
        let contactId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        if bytes.count >= 48 {
            let lat = readFloat32LE(bytes, offset: 36).map(Double.init)
            let lon = readFloat32LE(bytes, offset: 40).map(Double.init)
            let hasPosition = lat != 0.0 || lon != 0.0
            let rawName = Data(bytes.dropFirst(48))
            let nameEnd = rawName.firstIndex(of: 0) ?? rawName.endIndex
            let name = String(data: rawName[rawName.startIndex..<nameEnd], encoding: .utf8)
            return .nodeAdvert(
                contactId: contactId,
                name: name?.isEmpty == false ? name : nil,
                lat: hasPosition ? lat : nil,
                lon: hasPosition ? lon : nil
            )
        }
        return .nodeAdvert(contactId: contactId, name: nil, lat: nil, lon: nil)
    }

    /// Dekodiert einen einzelnen CONTACT (0x03) aus der GET_CONTACTS-Sequenz.
    /// Format: [pubkey:32][last_heard:4][flags:1][name:variable]
    private static func decodeContact(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 37 else {
            throw ProtocolError.invalidPayload("CONTACT payload zu kurz")
        }
        let contactId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        let lastHeardSecs = UInt32(bytes[32]) | UInt32(bytes[33]) << 8 |
                            UInt32(bytes[34]) << 16 | UInt32(bytes[35]) << 24
        let lastSeen: Date? = lastHeardSecs > 0
            ? Date(timeIntervalSince1970: TimeInterval(lastHeardSecs)) : nil
        let flags = bytes[36]
        let isOnline = (flags & 0x01) != 0
        let nameData = Data(bytes.dropFirst(37))
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        return .contact(MeshContact(
            id: contactId,
            name: name?.isEmpty == false ? name! : contactId,
            lastSeen: lastSeen,
            isOnline: isOnline,
            lat: nil,
            lon: nil
        ))
    }

    private static func decodeChannelMessage(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 3 else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG payload zu kurz")
        }
        let bytes = Array(payload)
        let channelIndex = Int(bytes[0])
        let hops = Int(bytes[1])
        let snrRaw = Int8(bitPattern: bytes[2])
        let textData = Data(bytes.dropFirst(3))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("Nachrichtentext kein gültiges UTF-8")
        }
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: channelIndex),
            senderName: "Unbekannt",
            text: text,
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: Float(snrRaw), routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        return .newChannelMessage(msg)
    }

    private static func decodeContactMessage(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 6 else {
            throw ProtocolError.invalidPayload("CONTACT_MSG payload zu kurz")
        }
        let bytes = Array(payload)
        let contactId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        let hops = Int(bytes[4])
        let snrRaw = Int8(bitPattern: bytes[5])
        let textData = Data(bytes.dropFirst(6))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("DM-Text kein gültiges UTF-8")
        }
        let msg = MeshMessage(
            id: UUID(),
            kind: .direct(contactId: contactId),
            senderName: contactId,
            text: text,
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: Float(snrRaw), routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        return .newDirectMessage(msg)
    }

    private static func decodeMsgAck(_ payload: Data) throws -> DecodedFrame {
        let msgId = payload.map { String(format: "%02x", $0) }.joined()
        return .messageAck(messageId: msgId)
    }

    // MARK: - Byte Helpers

    /// Liest Float32 little-endian aus einem Byte-Array ab `offset`.
    private static func readFloat32LE(_ bytes: [UInt8], offset: Int) -> Float? {
        guard offset + 3 < bytes.count else { return nil }
        let bits = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
        return Float(bitPattern: bits)
    }
}
