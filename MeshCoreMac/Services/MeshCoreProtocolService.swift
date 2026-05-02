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
        // VERIFY: Minimal-Frame. Echtes Spec-Format: [0x01][app_ver][reserved×6][app_name UTF-8].
        Data([MeshCoreProtocol.Command.appStart.rawValue])
    }

    static func encodeDeviceQuery() -> Data {
        // VERIFY: Minimal-Frame. Echtes Spec-Format: [0x16][app_target_ver].
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue])
    }

    static func encodeGetContacts() -> Data {
        Data([MeshCoreProtocol.Command.getContacts.rawValue])
    }

    /// Kodiert CMD_TRACE_PATH (0x07) mit 4-Byte Contact-ID-Präfix.
    /// VERIFY: Byte 0x07 und Format gegen reale Firmware bestätigen.
    static func encodeTracePath(contactId: String) -> Data {
        var bytes: [UInt8] = [MeshCoreProtocol.Command.tracePath.rawValue]
        let idBytes = stride(from: 0, to: min(contactId.count, 8), by: 2).compactMap {
            let start = contactId.index(contactId.startIndex, offsetBy: $0)
            let end = contactId.index(start, offsetBy: 2, limitedBy: contactId.endIndex) ?? contactId.endIndex
            return UInt8(contactId[start..<end], radix: 16)
        }
        bytes.append(contentsOf: idBytes.prefix(4))
        while bytes.count < 5 { bytes.append(0x00) }
        return Data(bytes)
    }

    static func encodeBattAndStorage() -> Data {
        Data([MeshCoreProtocol.Command.getBattAndStorage.rawValue])
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
        // VERIFY: Echtes CMD_SEND_CHANNEL_TXT_MSG (0x03) enthält zusätzlich Timestamp und 0x00-Padding.
        // DM-Format benötigt 6-Byte pubkey-Prefix für Recipient-Adressierung (Phase 2+).
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
            case .battAndStorage:
                return try decodeBattAndStorage(payload)
            case .ok, .err, .currTime, .noMoreMessages:
                throw ProtocolError.unknownCommand(commandByte)
            }
        }

        if let push = MeshCoreProtocol.Push(rawValue: commandByte) {
            switch push {
            case .sendConfirmed:
                return try decodeMsgAck(payload)
            case .advert, .pathUpdated:
                return try decodeNodeAdvertPush(payload)
            case .statusResponse:
                return try decodeStatusResponse(payload)
            case .msgWaiting, .rawData, .loginSuccess, .loginFail:
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
    private static func decodeNodeAdvertPush(_ payload: Data) throws -> DecodedFrame {
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
        let rawName = Data(bytes.dropFirst(37))
        let nameEnd = rawName.firstIndex(of: 0) ?? rawName.endIndex
        let name = String(data: rawName[rawName.startIndex..<nameEnd], encoding: .utf8)
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

    /// Dekodiert RESP_BATT_AND_STORAGE (0x0C).
    /// Format (VERIFY): [battery_pct:1][storage_used_le32:4][storage_free_le32:4]
    private static func decodeBattAndStorage(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 9 else {
            throw ProtocolError.invalidPayload("BATT_AND_STORAGE zu kurz")
        }
        let battery = Int(bytes[0])
        let used = Int(UInt32(bytes[1]) | UInt32(bytes[2]) << 8 |
                       UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24)
        let free = Int(UInt32(bytes[5]) | UInt32(bytes[6]) << 8 |
                       UInt32(bytes[7]) << 16 | UInt32(bytes[8]) << 24)
        return .battAndStorage(battery: battery, storageUsed: used, storageFree: free)
    }

    /// Dekodiert PUSH_STATUS_RESPONSE (0x87).
    /// Format (VERIFY): [rssi_signed:1][noise_signed:1]
    private static func decodeStatusResponse(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 2 else {
            throw ProtocolError.invalidPayload("STATUS_RESPONSE zu kurz")
        }
        let rssi = Int(Int8(bitPattern: bytes[0]))
        let noise = Int(Int8(bitPattern: bytes[1]))
        return .noiseFloor(rssi: rssi, noise: noise)
    }
}
