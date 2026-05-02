// MeshCoreMac/Services/MeshCoreProtocolService.swift
//
// Encode/Decode für das MeshCore Companion-BLE-Protokoll.
// Quelle: https://docs.meshcore.io/companion_protocol/
//
// Bekannte Decode-Abweichungen von der Spec (Phase 4 Fix):
//   SELF_INFO (0x05): Name ab Byte 58, lat/lon int32÷1e6 — aktuell float32 ab Byte 36
//   ADVERT  (0x80):  lat/lon in Appdata ab Byte 100 mit Flags — aktuell float32 ab Byte 36
//   BATTERY  (0x0C): voltage_mV (uint16) + used_kb + total_kb — aktuell pct + used_B + free_B
//   CH_MSG   (0x08): hat kein SNR-Feld; [ch][path_len][txt_type][ts:4][msg] — aktuell [ch][hops][snr][msg]

import Foundation

enum MeshCoreProtocolService {

    // MARK: - Encoder

    /// CMD_APP_START: [0x01][reserved×7][app_name UTF-8]
    static func encodeAppStart() -> Data {
        var frame = Data([MeshCoreProtocol.Command.appStart.rawValue])
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        frame.append(contentsOf: "MeshCoreMac".utf8)
        return frame
    }

    /// CMD_DEVICE_QUERY: Spec zeigt [0x16][0x03] — VERIFY mit echter Hardware.
    static func encodeDeviceQuery() -> Data {
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue, 0x03])
    }

    static func encodeGetContacts() -> Data {
        Data([MeshCoreProtocol.Command.getContacts.rawValue])
    }

    static func encodeGetMessage() -> Data {
        Data([MeshCoreProtocol.Command.getMessage.rawValue])
    }

    /// CMD_GET_CHANNEL_INFO: [0x1F][ch_idx:1]
    static func encodeGetChannelInfo(index: UInt8) -> Data {
        Data([MeshCoreProtocol.Command.getChannelInfo.rawValue, index])
    }

    /// CMD_SET_CHANNEL: [0x20][ch_idx:1][name:32 null-padded][secret:16]
    static func encodeSetChannel(index: UInt8, name: String, secret: Data = Data(repeating: 0, count: 16)) -> Data {
        var frame = Data([MeshCoreProtocol.Command.setChannel.rawValue, index])
        var nameBytes = Array(name.utf8.prefix(MeshCoreProtocol.maxChannelNameLength))
        while nameBytes.count < MeshCoreProtocol.maxChannelNameLength { nameBytes.append(0x00) }
        frame.append(contentsOf: nameBytes)
        let secretBytes = secret.prefix(MeshCoreProtocol.channelSecretLength)
        frame.append(contentsOf: secretBytes)
        while frame.count < 2 + MeshCoreProtocol.maxChannelNameLength + MeshCoreProtocol.channelSecretLength {
            frame.append(0x00)
        }
        return frame
    }

    /// CMD_TRACE_PATH: VERIFY Byte-Wert und Format.
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

    /// VERIFY: Echtes CMD_SEND_CHANNEL_TXT_MSG (0x03): [0x03][0x00][ch_idx][ts:4][msg].
    /// DM (0x02) benötigt 6-Byte-Pubkey-Prefix. Beides in Phase 4 korrigieren.
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
            case .battAndStorage:
                return try decodeBattAndStorage(payload)
            case .channelInfo:
                return try decodeChannelInfo(payload)
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

    /// Dekodiert SELF_INFO (0x05) und DEVICE_INFO (0x0D).
    /// PHASE4: Aktuell wird DEVICE_INFO (0x0D) identisch zu SELF_INFO behandelt — falsch.
    /// PHASE4: lat/lon sind int32÷1e6 bei Offset 36–43, Name ab Byte 58 (nicht 48).
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
        let firmware = String(data: Data(bytes.dropFirst(4)), encoding: .utf8) ?? "unbekannt"
        return .selfInfo(nodeId: nodeId, lat: nil, lon: nil, firmware: firmware)
    }

    /// Dekodiert ADVERT (0x80) und PATH_UPDATED (0x81).
    /// PHASE4: Echter Aufbau: [pubkey:32][ts:4][signature:64][appdata mit Flags ab Byte 100].
    /// Aktuell wird float32 bei Offset 36–43 gelesen (falsch für echte Frames).
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

    /// Dekodiert CONTACT (0x03): [pubkey:32][last_heard:4][flags:1][name:variable]
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

    /// Dekodiert CHANNEL_MSG_RECV (0x08).
    /// PHASE4: Spec-Format: [ch_idx:1][path_len:1][txt_type:1][ts:4][msg].
    /// Aktuell: [ch_idx:1][hops:1][snr:1][msg] — kein Timestamp, SNR-Byte ist txt_type.
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

    /// Dekodiert CONTACT_MSG_RECV (0x07).
    /// PHASE4: Spec-Format: [pubkey_prefix:6][path_len:1][txt_type:1][ts:4][msg].
    /// Aktuell: [contact_id:4][hops:1][snr:1][msg].
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

    /// Dekodiert PACKET_BATTERY (0x0C).
    /// PHASE4: Spec: [voltage_mv:2 LE][used_kb:4 LE][total_kb:4 LE].
    /// Aktuell: [batt_pct:1][used_b:4 LE][free_b:4 LE] — falsch.
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

    /// Dekodiert PUSH_STATUS_RESPONSE (0x87): [rssi_i8:1][noise_i8:1].
    private static func decodeStatusResponse(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 2 else {
            throw ProtocolError.invalidPayload("STATUS_RESPONSE zu kurz")
        }
        let rssi = Int(Int8(bitPattern: bytes[0]))
        let noise = Int(Int8(bitPattern: bytes[1]))
        return .noiseFloor(rssi: rssi, noise: noise)
    }

    /// Dekodiert PACKET_CHANNEL_INFO (0x12): [ch_idx:1][name:32][secret:16]
    private static func decodeChannelInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 49 else {
            throw ProtocolError.invalidPayload("CHANNEL_INFO payload zu kurz")
        }
        let index = Int(bytes[0])
        let nameBytes = Data(bytes[1...32])
        let nameEnd = nameBytes.firstIndex(of: 0) ?? nameBytes.endIndex
        let name = String(data: nameBytes[nameBytes.startIndex..<nameEnd], encoding: .utf8) ?? ""
        let secret = Data(bytes[33..<49])
        return .channelInfo(index: index, name: name, secret: secret)
    }

    // MARK: - Byte Helpers

    private static func readFloat32LE(_ bytes: [UInt8], offset: Int) -> Float? {
        guard offset + 3 < bytes.count else { return nil }
        let bits = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
        return Float(bitPattern: bits)
    }
}
