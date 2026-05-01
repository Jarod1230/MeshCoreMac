// MeshCoreMac/Services/MeshCoreProtocolService.swift
//
// Encode/Decode für das MeshCore Companion-BLE-Protokoll.
//
// Quelle: https://docs.meshcore.io/companion_protocol/
//         https://github.com/meshcore-dev/MeshCore/wiki/Companion-Radio-Protocol
//
// Das echte V3-Frame-Format für Channel/Contact-Messages ist umfangreicher
// (Timestamp, pubkey-Prefix, Pfad, SNR×0.25). Für Phase 1 implementieren wir
// einen reduzierten Decoder, der die im Plan/Tests definierten Felder liefert.
// VERIFY: Vor BLE-Service-Integration (Task 5) gegen reale Firmware-Frames
//         abgleichen und ggf. erweitern.

import Foundation

enum MeshCoreProtocolService {

    // MARK: - Encoder

    /// CMD_APP_START: muss als erstes nach Verbindungsaufbau gesendet werden.
    /// Format laut Spec: [0x01][app_ver][reserved×6][app_name UTF-8].
    /// Phase 1: Minimal-Frame mit nur dem Command-Byte (Firmware ignoriert
    /// fehlende Reserved-Bytes laut älterer Spec). VERIFY mit echter Firmware.
    static func encodeAppStart() -> Data {
        Data([MeshCoreProtocol.Command.appStart.rawValue])
    }

    /// CMD_DEVICE_QUERY: fragt Device-Info an.
    /// Format laut Spec: [0x16][app_target_ver]. Phase 1: nur Command-Byte.
    /// VERIFY mit echter Firmware.
    static func encodeDeviceQuery() -> Data {
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue])
    }

    /// Encodiert eine Textnachricht.
    ///
    /// - Channel-Message: `[0x02][channelIndex][text]` (Plan-Spec für Tests).
    ///   Echtes Spec-Frame `CMD_SEND_CHANNEL_TXT_MSG (0x03)` enthält zusätzlich
    ///   timestamp und 0x00-Padding-Byte. VERIFY für Task 5.
    /// - DM: `[0x02][channelIndex=0][text]`. Recipient-Adressierung in Phase 1
    ///   nicht implementiert. VERIFY für DM-Support (echtes Spec verwendet
    ///   pubkey_prefix mit 6 Bytes).
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
        // Frame: [CMD][channelIndex][text_utf8...]
        var frame = Data([MeshCoreProtocol.Command.sendTxtMsg.rawValue, channelIndex])
        frame.append(textData)
        return frame
    }

    // MARK: - Decoder

    /// Dispatcht einen eingehenden Frame anhand des Command-Bytes.
    static func decodeFrame(_ data: Data) throws -> DecodedFrame {
        guard !data.isEmpty else { throw ProtocolError.emptyFrame }

        let commandByte = data[data.startIndex]
        let payload = data.dropFirst()

        // Sync-Responses
        if let response = MeshCoreProtocol.Response(rawValue: commandByte) {
            switch response {
            case .deviceInfo, .selfInfo:
                return try decodeDeviceInfo(payload)
            case .channelMsgRecv:
                return try decodeChannelMessage(payload)
            case .contactMsgRecv:
                return try decodeContactMessage(payload)
            case .sent:
                return try decodeMsgAck(payload)
            default:
                throw ProtocolError.unknownCommand(commandByte)
            }
        }

        // Push-Notifications
        if let push = MeshCoreProtocol.Push(rawValue: commandByte) {
            switch push {
            case .sendConfirmed:
                return try decodeMsgAck(payload)
            case .advert, .pathUpdated:
                return try decodeNodeStatusFromAdvert(payload, isOnline: true)
            default:
                throw ProtocolError.unknownCommand(commandByte)
            }
        }

        throw ProtocolError.unknownCommand(commandByte)
    }

    // MARK: - Private Decode Helpers

    /// Reduzierter DEVICE_INFO/SELF_INFO Decode für Phase 1.
    /// Echtes Spec-Format ist deutlich größer (32-Byte pubkey, lat/lon, etc.).
    /// VERIFY: Vor Task 5 gegen reale Firmware-Frames abgleichen.
    private static func decodeDeviceInfo(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 2 else {
            throw ProtocolError.invalidPayload("DEVICE_INFO payload zu kurz")
        }
        let nodeId = payload.prefix(4).map { String(format: "%02x", $0) }.joined()
        let firmware = String(data: payload.dropFirst(4), encoding: .utf8) ?? "unbekannt"
        return .deviceInfo(nodeId: nodeId, firmwareVersion: firmware)
    }

    /// Channel-Message Decode (Plan-Format für TDD-Tests).
    ///
    /// Frame nach Command-Byte: `[channelIndex][hops][snr_raw_signed][text_utf8...]`
    ///
    /// VERIFY: Echtes V3-Format (`RESP_CODE_CHANNEL_MSG_RECV_V3 = 0x11`)
    ///         enthält zusätzlich sender_timestamp (uint32 LE) und längere
    ///         Header. SNR wird als signed_byte × 0.25 dB skaliert. Phase 1
    ///         arbeitet zunächst mit dem reduzierten Plan-Frame.
    private static func decodeChannelMessage(_ payload: Data) throws -> DecodedFrame {
        guard payload.count >= 3 else {
            throw ProtocolError.invalidPayload("CHANNEL_MSG payload zu kurz")
        }
        let bytes = Array(payload)
        let channelIndex = Int(bytes[0])
        let hops = Int(bytes[1])
        let snrRaw = Int8(bitPattern: bytes[2])
        // VERIFY: Skalierung für V3 ist 0.25; im Plan-Frame ungescaled.
        let snr = Float(snrRaw)
        let textData = Data(bytes.dropFirst(3))
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("Nachrichtentext kein gültiges UTF-8")
        }
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: channelIndex),
            senderName: "Unbekannt",  // VERIFY: Echtes Frame liefert pubkey-Prefix
            text: text,
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: snr, routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        return .newChannelMessage(msg)
    }

    /// Contact-Message (DM) Decode.
    ///
    /// Frame nach Command-Byte: `[contactId×4][hops][snr_raw_signed][text_utf8...]`
    /// VERIFY: Echtes V3-Format weicht ab (pubkey-Prefix 6 Bytes).
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

    /// Send-Confirmed / ACK-Decode.
    /// VERIFY: Echtes ACK-Format spezifizieren (vermutlich message-hash).
    private static func decodeMsgAck(_ payload: Data) throws -> DecodedFrame {
        let msgId = payload.map { String(format: "%02x", $0) }.joined()
        return .messageAck(messageId: msgId)
    }

    /// PUSH_CODE_ADVERT: pubkey eines neu gesehenen Nodes.
    /// Format: [pubkey×32]. Wir nehmen die ersten 4 Bytes als contactId.
    /// VERIFY: für Phase 1 ausreichend; ContactStore wird in Task 4/5 erweitert.
    private static func decodeNodeStatusFromAdvert(
        _ payload: Data,
        isOnline: Bool
    ) throws -> DecodedFrame {
        guard payload.count >= 4 else {
            throw ProtocolError.invalidPayload("ADVERT payload zu kurz")
        }
        let contactId = payload.prefix(4).map { String(format: "%02x", $0) }.joined()
        return .nodeStatus(contactId: contactId, isOnline: isOnline)
    }
}
