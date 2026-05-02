// MeshCoreMac/Services/MeshCoreProtocolService.swift
// Quelle: https://docs.meshcore.io/companion_protocol/ (Stand: Mai 2026)

import Foundation

enum MeshCoreProtocolService {

    // MARK: - Encoder

    /// CMD_APP_START: [0x01][reserved×7]["MeshCoreMac" UTF-8]
    static func encodeAppStart() -> Data {
        var frame = Data([MeshCoreProtocol.Command.appStart.rawValue])
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        frame.append(contentsOf: "MeshCoreMac".utf8)
        return frame
    }

    /// CMD_DEVICE_QUERY: [0x16][0x03]
    static func encodeDeviceQuery() -> Data {
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue, 0x03])
    }

    static func encodeGetContacts() -> Data {
        Data([MeshCoreProtocol.Command.getContacts.rawValue])
    }

    static func encodeGetMessage() -> Data {
        Data([MeshCoreProtocol.Command.getMessage.rawValue])
    }

    /// CMD_GET_CHANNEL_INFO: [0x1F][ch_idx]
    static func encodeGetChannelInfo(index: UInt8) -> Data {
        Data([MeshCoreProtocol.Command.getChannelInfo.rawValue, index])
    }

    /// CMD_SET_CHANNEL: [0x20][ch_idx][name:32 null-padded][secret:16]
    static func encodeSetChannel(index: UInt8, name: String, secret: Data = Data(repeating: 0, count: 16)) -> Data {
        var frame = Data([MeshCoreProtocol.Command.setChannel.rawValue, index])
        var nameBytes = Array(name.utf8.prefix(MeshCoreProtocol.maxChannelNameLength))
        while nameBytes.count < MeshCoreProtocol.maxChannelNameLength { nameBytes.append(0x00) }
        frame.append(contentsOf: nameBytes)
        var secretBytes = Array(secret.prefix(MeshCoreProtocol.channelSecretLength))
        while secretBytes.count < MeshCoreProtocol.channelSecretLength { secretBytes.append(0x00) }
        frame.append(contentsOf: secretBytes)
        return frame
    }

    /// CMD_TRACE_PATH: VERIFY Byte-Wert und Format mit echter Hardware.
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

    /// Kanal-Nachricht: [0x03][0x00][ch_idx][timestamp:4 LE][msg UTF-8]
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
        if recipientId == nil {
            let ts = UInt32(Date().timeIntervalSince1970)
            var frame = Data([MeshCoreProtocol.Command.sendChannelTxtMsg.rawValue, 0x00, channelIndex])
            frame.append(UInt8(ts & 0xFF))
            frame.append(UInt8((ts >> 8) & 0xFF))
            frame.append(UInt8((ts >> 16) & 0xFF))
            frame.append(UInt8((ts >> 24) & 0xFF))
            frame.append(textData)
            return frame
        } else {
            // DM — VERIFY: echtes Format benötigt 6-Byte Pubkey-Prefix
            var frame = Data([MeshCoreProtocol.Command.sendTxtMsg.rawValue, channelIndex])
            frame.append(textData)
            return frame
        }
    }

    // MARK: - Decoder

    static func decodeFrame(_ data: Data) throws -> DecodedFrame {
        guard !data.isEmpty else { throw ProtocolError.emptyFrame }
        let commandByte = data[data.startIndex]
        let payload = data.dropFirst()

        if let response = MeshCoreProtocol.Response(rawValue: commandByte) {
            switch response {
            case .selfInfo:
                return try decodeSelfInfo(payload)
            case .deviceInfo:
                return try decodeDeviceInfo(payload)
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

        if let v3 = MeshCoreProtocol.ResponseV3(rawValue: commandByte) {
            switch v3 {
            case .channelMsgRecvV3:
                return try decodeChannelMessageV3(payload)
            case .contactMsgRecvV3:
                return try decodeContactMessageV3(payload)
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

    // MARK: - Private Decoder

    /// PACKET_SELF_INFO (0x05) — Spec-korrekt:
    /// payload[0]: advert_type, [1]: tx_power, [2]: max_tx_power
    /// payload[3-34]: pubkey (32B), nodeId = prefix 4B
    /// payload[35-38]: lat int32 LE ÷ 1_000_000
    /// payload[39-42]: lon int32 LE ÷ 1_000_000
    /// payload[43-56]: multi_acks, policy, telemetry, manual, freq(4), bw(4), sf, cr
    /// payload[57+]: device name UTF-8
    private static func decodeSelfInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 7 else {
            throw ProtocolError.invalidPayload("SELF_INFO payload zu kurz")
        }
        let nodeId = bytes[3..<7].map { String(format: "%02x", $0) }.joined()
        let lat: Double?
        let lon: Double?
        if bytes.count >= 43 {
            let latI32 = readInt32LE(bytes, offset: 35)
            let lonI32 = readInt32LE(bytes, offset: 39)
            lat = latI32 != 0 ? Double(latI32) / 1_000_000.0 : nil
            lon = lonI32 != 0 ? Double(lonI32) / 1_000_000.0 : nil
        } else {
            lat = nil; lon = nil
        }
        let freqHz: UInt32 = bytes.count >= 52 ? readUInt32LE(bytes, offset: 47) : 0
        let bwHz: UInt32   = bytes.count >= 56 ? readUInt32LE(bytes, offset: 51) : 0
        let sf: UInt8      = bytes.count >= 56 ? bytes[55] : 0
        let cr: UInt8      = bytes.count >= 57 ? bytes[56] : 0
        let firmware: String
        if bytes.count > 57 {
            let nameBytes = Data(bytes[57...])
            let nameEnd = nameBytes.firstIndex(of: 0) ?? nameBytes.endIndex
            firmware = String(data: nameBytes[nameBytes.startIndex..<nameEnd], encoding: .utf8) ?? "unbekannt"
        } else {
            firmware = "unbekannt"
        }
        return .selfInfo(nodeId: nodeId, lat: lat, lon: lon, firmware: firmware,
                         radioFrequencyHz: freqHz, radioBandwidthHz: bwHz,
                         radioSpreadingFactor: sf, radioCodingRate: cr)
    }

    /// PACKET_DEVICE_INFO (0x0D) — Spec-korrekt:
    /// payload[0]: fw_ver, [1]: max_contacts_raw (×2), [2]: max_channels
    /// payload[3-6]: BLE PIN (uint32 LE)
    /// payload[7-18]: fw_build (12B UTF-8)
    /// payload[19-58]: model (40B UTF-8)
    /// payload[59-78]: version (20B UTF-8)
    private static func decodeDeviceInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 3 else {
            throw ProtocolError.invalidPayload("DEVICE_INFO payload zu kurz")
        }
        let fwVersion  = Int(bytes[0])
        let maxContacts = Int(bytes[1]) * 2
        let maxChannels = Int(bytes[2])
        func nullTerminatedString(_ slice: ArraySlice<UInt8>) -> String {
            let data = Data(slice)
            let end = data.firstIndex(of: 0) ?? data.endIndex
            return String(data: data[data.startIndex..<end], encoding: .utf8) ?? ""
        }
        let build   = bytes.count >= 19 ? nullTerminatedString(bytes[7..<19]) : ""
        let model   = bytes.count >= 59 ? nullTerminatedString(bytes[19..<59]) : ""
        let version = bytes.count >= 79 ? nullTerminatedString(bytes[59..<79]) : ""
        let info = NodeInfo(
            nodeId: "",
            firmwareVersion: fwVersion,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            firmwareBuild: build,
            model: model,
            version: version,
            radioFrequencyHz: 0,
            radioBandwidthHz: 0,
            radioSpreadingFactor: 0,
            radioCodingRate: 0
        )
        return .deviceInfo(info)
    }

    /// PACKET_ADVERTISEMENT (0x80) / PATH_UPDATED (0x81) — Spec-korrekt:
    /// payload[0-31]: pubkey, [32-35]: ts, [36-99]: signature (64B)
    /// payload[100]: appdata flags
    ///   flag & 0x10: lat int32 LE ÷ 1e6 (4B), lon int32 LE ÷ 1e6 (4B)
    ///   flag & 0x80: name UTF-8 (variable)
    private static func decodeNodeAdvertPush(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 4 else {
            throw ProtocolError.invalidPayload("ADVERT payload zu kurz")
        }
        let contactId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        var lat: Double? = nil
        var lon: Double? = nil
        var name: String? = nil
        if bytes.count > 100 {
            let flags = bytes[100]
            var offset = 101
            if flags & 0x10 != 0, offset + 8 <= bytes.count {
                let latI32 = readInt32LE(bytes, offset: offset)
                let lonI32 = readInt32LE(bytes, offset: offset + 4)
                offset += 8
                if latI32 != 0 || lonI32 != 0 {
                    lat = Double(latI32) / 1_000_000.0
                    lon = Double(lonI32) / 1_000_000.0
                }
            }
            if flags & 0x80 != 0, offset < bytes.count {
                let nameBytes = Data(bytes[offset...])
                let nameEnd = nameBytes.firstIndex(of: 0) ?? nameBytes.endIndex
                name = String(data: nameBytes[nameBytes.startIndex..<nameEnd], encoding: .utf8)
            }
        }
        return .nodeAdvert(contactId: contactId,
                           name: name?.isEmpty == false ? name : nil,
                           lat: lat, lon: lon)
    }

    /// CONTACT (0x03): [pubkey:32][last_heard:4][flags:1][name:variable]
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
        let isOnline = (bytes[36] & 0x01) != 0
        let rawName = Data(bytes.dropFirst(37))
        let nameEnd = rawName.firstIndex(of: 0) ?? rawName.endIndex
        let name = String(data: rawName[rawName.startIndex..<nameEnd], encoding: .utf8)
        return .contact(MeshContact(
            id: contactId,
            name: name?.isEmpty == false ? name! : contactId,
            lastSeen: lastSeen,
            isOnline: isOnline,
            lat: nil, lon: nil
        ))
    }

    /// CHANNEL_MSG_RECV (0x08) — Spec-korrekt:
    /// payload[0]: ch_idx, [1]: path_len (=hops), [2]: txt_type, [3-6]: timestamp, [7+]: msg
    private static func decodeChannelMessage(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 7 else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG payload zu kurz")
        }
        let bytes = Array(payload)
        let channelIndex = Int(bytes[0])
        let hops         = Int(bytes[1])
        let textData = Data(bytes.dropFirst(7))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG kein gültiges UTF-8")
        }
        return .newChannelMessage(MeshMessage(
            id: UUID(), kind: .channel(index: channelIndex),
            senderName: "Unbekannt", text: text, timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: 0, routeDisplay: nil),
            deliveryStatus: .delivered, isIncoming: true
        ))
    }

    /// CHANNEL_MSG_RECV_V3 (0x11):
    /// payload[0]: snr_i8 (÷4 = dB), [1-2]: reserved, [3]: ch_idx, [4]: path_len, [5]: txt_type, [6-9]: ts, [10+]: msg
    private static func decodeChannelMessageV3(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 10 else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG_V3 payload zu kurz")
        }
        let bytes = Array(payload)
        let snr          = Float(Int8(bitPattern: bytes[0])) / 4.0
        let channelIndex = Int(bytes[3])
        let hops         = Int(bytes[4])
        let textData     = Data(bytes.dropFirst(10))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG_V3 kein gültiges UTF-8")
        }
        return .newChannelMessage(MeshMessage(
            id: UUID(), kind: .channel(index: channelIndex),
            senderName: "Unbekannt", text: text, timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: snr, routeDisplay: nil),
            deliveryStatus: .delivered, isIncoming: true
        ))
    }

    /// CONTACT_MSG_RECV (0x07) — Spec-korrekt:
    /// payload[0-5]: pubkey_prefix (6B), [6]: path_len, [7]: txt_type, [8-11]: ts, [12+]: msg
    private static func decodeContactMessage(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 12 else {
            throw ProtocolError.invalidPayload("CONTACT_MSG payload zu kurz")
        }
        let bytes = Array(payload)
        let contactId = bytes.prefix(4).map { String(format: "%02x", $0) }.joined()
        let hops      = Int(bytes[6])
        let textData  = Data(bytes.dropFirst(12))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("CONTACT_MSG kein gültiges UTF-8")
        }
        return .newDirectMessage(MeshMessage(
            id: UUID(), kind: .direct(contactId: contactId),
            senderName: contactId, text: text, timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: 0, routeDisplay: nil),
            deliveryStatus: .delivered, isIncoming: true
        ))
    }

    /// CONTACT_MSG_RECV_V3 (0x10):
    /// payload[0]: snr_i8 (÷4), [1-2]: reserved, [3-8]: pubkey_prefix (6B), [9]: path_len, [10]: txt_type, [11-14]: ts, [15+]: msg
    private static func decodeContactMessageV3(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 15 else {
            throw ProtocolError.invalidPayload("CONTACT_MSG_V3 payload zu kurz")
        }
        let bytes = Array(payload)
        let snr       = Float(Int8(bitPattern: bytes[0])) / 4.0
        let contactId = bytes[3..<7].map { String(format: "%02x", $0) }.joined()
        let hops      = Int(bytes[9])
        let textData  = Data(bytes.dropFirst(15))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("CONTACT_MSG_V3 kein gültiges UTF-8")
        }
        return .newDirectMessage(MeshMessage(
            id: UUID(), kind: .direct(contactId: contactId),
            senderName: contactId, text: text, timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: snr, routeDisplay: nil),
            deliveryStatus: .delivered, isIncoming: true
        ))
    }

    private static func decodeMsgAck(_ payload: Data) throws -> DecodedFrame {
        let msgId = payload.map { String(format: "%02x", $0) }.joined()
        return .messageAck(messageId: msgId)
    }

    /// PACKET_BATTERY (0x0C) — Spec-korrekt:
    /// payload[0-1]: voltage_mV (uint16 LE), [2-5]: used_KB (uint32 LE), [6-9]: total_KB (uint32 LE)
    private static func decodeBattAndStorage(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 10 else {
            throw ProtocolError.invalidPayload("BATT_AND_STORAGE zu kurz")
        }
        let voltageMillivolts = Int(UInt16(bytes[0]) | UInt16(bytes[1]) << 8)
        let usedKB   = Int(UInt32(bytes[2]) | UInt32(bytes[3]) << 8 |
                           UInt32(bytes[4]) << 16 | UInt32(bytes[5]) << 24)
        let totalKB  = Int(UInt32(bytes[6]) | UInt32(bytes[7]) << 8 |
                           UInt32(bytes[8]) << 16 | UInt32(bytes[9]) << 24)
        return .battAndStorage(voltageMillivolts: voltageMillivolts,
                               storageUsedKB: usedKB, storageTotalKB: totalKB)
    }

    /// PUSH_STATUS_RESPONSE (0x87): [rssi_i8:1][noise_i8:1]
    private static func decodeStatusResponse(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 2 else {
            throw ProtocolError.invalidPayload("STATUS_RESPONSE zu kurz")
        }
        return .noiseFloor(rssi: Int(Int8(bitPattern: bytes[0])),
                           noise: Int(Int8(bitPattern: bytes[1])))
    }

    /// PACKET_CHANNEL_INFO (0x12): [ch_idx:1][name:32][secret:16]
    private static func decodeChannelInfo(_ payload: Data) throws -> DecodedFrame {
        let bytes = Array(payload)
        guard bytes.count >= 49 else {
            throw ProtocolError.invalidPayload("CHANNEL_INFO payload zu kurz")
        }
        let index    = Int(bytes[0])
        let nameBytes = Data(bytes[1...32])
        let nameEnd  = nameBytes.firstIndex(of: 0) ?? nameBytes.endIndex
        let name     = String(data: nameBytes[nameBytes.startIndex..<nameEnd], encoding: .utf8) ?? ""
        let secret   = Data(bytes[33..<49])
        return .channelInfo(index: index, name: name, secret: secret)
    }

    // MARK: - Byte Helpers

    private static func readInt32LE(_ bytes: [UInt8], offset: Int) -> Int32 {
        guard offset + 3 < bytes.count else { return 0 }
        return Int32(bitPattern:
            UInt32(bytes[offset]) |
            UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 |
            UInt32(bytes[offset + 3]) << 24)
    }

    private static func readUInt32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset]) |
               UInt32(bytes[offset + 1]) << 8 |
               UInt32(bytes[offset + 2]) << 16 |
               UInt32(bytes[offset + 3]) << 24
    }
}
