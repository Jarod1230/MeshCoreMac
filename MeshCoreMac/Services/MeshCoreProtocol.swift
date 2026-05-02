// MeshCoreMac/Services/MeshCoreProtocol.swift
//
// MeshCore Companion Radio Protocol
// Quelle: https://docs.meshcore.io/companion_protocol/
//
// Alle Byte-Werte gegen die offizielle Spec geprüft (Stand: Mai 2026).
// Decode-Logik für SELF_INFO, ADVERT und BATTERY weicht noch ab —
// das wird in Phase 4 korrigiert (// PHASE4: Kommentare markieren die Stellen).

import CoreBluetooth
import Foundation

enum MeshCoreProtocol {
    // MARK: - BLE UUIDs (Nordic UART Service)
    // Verifiziert via offizieller MeshCore Companion-Spec.
    // CBUUID ist in Apple's Frameworks nicht als Sendable markiert, ist aber
    // de-facto immutable nach Initialisierung. Daher nonisolated(unsafe).
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    /// App → Node (Write-Endpoint aus App-Sicht).
    nonisolated(unsafe) static let txCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Node → App (Notify-Endpoint).
    nonisolated(unsafe) static let rxCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // MARK: - Commands (App → Node)
    // Quelle: https://docs.meshcore.io/companion_protocol/
    enum Command: UInt8 {
        case appStart           = 0x01  // CMD_APP_START: [0x01][reserved×7][app_name UTF-8]
        case sendTxtMsg         = 0x02  // CMD_SEND_TXT_MSG (DM) — VERIFY: Format gegen Spec prüfen
        case sendChannelTxtMsg  = 0x03  // CMD_SEND_CHANNEL_TXT_MSG: [0x03][0x00][ch_idx][ts:4][msg]
        case getContacts        = 0x04  // CMD_GET_CONTACTS
        case getDeviceTime      = 0x05  // CMD_GET_DEVICE_TIME — VERIFY: nicht in aktueller Spec
        case tracePath          = 0x07  // CMD_TRACE_PATH — VERIFY: Byte-Wert unbestätigt
        case getMessage         = 0x0A  // CMD_GET_MESSAGE (Polling nach PACKET_MESSAGES_WAITING)
        case getBattAndStorage  = 0x14  // CMD_GET_BATT_AND_STORAGE
        case deviceQuery        = 0x16  // CMD_DEVICE_QUERY: spec zeigt [0x16][0x03] — VERIFY
        case getChannelInfo     = 0x1F  // CMD_GET_CHANNEL_INFO: [0x1F][ch_idx:1]
        case setChannel         = 0x20  // CMD_SET_CHANNEL: [0x20][ch_idx:1][name:32][secret:16]
    }

    // MARK: - Responses (Node → App, synchron auf Command)
    // Quelle: https://docs.meshcore.io/companion_protocol/
    enum Response: UInt8 {
        case ok                = 0x00  // PACKET_OK: [0x00][optional_value:4 LE]
        case err               = 0x01  // PACKET_ERROR: [0x01][error_code:1]
        case contactsStart     = 0x02  // CONTACTS_START
        case contact           = 0x03  // CONTACT: [pubkey:32][last_heard:4][flags:1][name]
        case endOfContacts     = 0x04  // END_OF_CONTACTS
        /// PACKET_SELF_INFO: [advert_type:1][tx_pwr:1][max_tx_pwr:1][pubkey:32]
        /// [lat_i32_le÷1e6:4][lon_i32_le÷1e6:4][flags…:10][name:variable from byte 58]
        /// PHASE4: Decoder liest aktuell float32 bei Offset 36–43 und Name ab Byte 48.
        /// Korrekt wäre int32÷1e6 bei Offset 36–43 und Name ab Byte 58.
        case selfInfo          = 0x05  // PACKET_SELF_INFO
        case sent              = 0x06  // PACKET_MSG_SENT: [route_flag:1][tag:4][timeout_ms:4]
        case contactMsgRecv    = 0x07  // PACKET_CONTACT_MSG_RECV: [pubkey_prefix:6][path_len:1][txt_type:1][ts:4][msg]
        /// PACKET_CHANNEL_MSG_RECV: [ch_idx:1][path_len:1][txt_type:1][ts:4][msg]
        /// PHASE4: Decoder liest aktuell [ch_idx][hops][snr_raw][msg]. SNR gibt es nur in V3 (0x11).
        case channelMsgRecv    = 0x08  // PACKET_CHANNEL_MSG_RECV
        case currTime          = 0x09  // RESP_CURR_TIME — für Phase 4 (Decoder fehlt noch)
        case noMoreMessages    = 0x0A  // PACKET_NO_MORE_MSGS
        case battAndStorage    = 0x0C  // PACKET_BATTERY: [voltage_mv:2 LE][used_kb:4 LE][total_kb:4 LE]
                                       // PHASE4: Decoder liest aktuell [batt_pct:1][used_b:4][free_b:4].
        /// PACKET_DEVICE_INFO: völlig anderes Format als SELF_INFO —
        /// [fw_ver:1][max_contacts_raw:1][max_ch:1][ble_pin:4][fw_build:12][model:40][version:20]
        /// PHASE4: Decoder leitet aktuell zu decodeNodeInfo weiter (falsch).
        case deviceInfo        = 0x0D  // PACKET_DEVICE_INFO
        case channelInfo       = 0x12  // PACKET_CHANNEL_INFO: [ch_idx:1][name:32][secret:16]
    }

    // MARK: - V3-Responses mit SNR
    // Quelle: https://docs.meshcore.io/companion_protocol/
    enum ResponseV3: UInt8 {
        /// [snr_i8÷4:1][reserved:2][pubkey_prefix:6][path_len:1][txt_type:1][ts:4][msg]
        case contactMsgRecvV3  = 0x10  // PACKET_CONTACT_MSG_RECV_V3
        /// [snr_i8÷4:1][reserved:2][ch_idx:1][path_len:1][txt_type:1][ts:4][msg]
        case channelMsgRecvV3  = 0x11  // PACKET_CHANNEL_MSG_RECV_V3
    }

    // MARK: - Push-Notifications (Node → App, asynchron)
    // Quelle: https://docs.meshcore.io/companion_protocol/
    enum Push: UInt8 {
        /// PACKET_ADVERTISEMENT: [pubkey:32][ts:4][signature:64][appdata…]
        /// Appdata-Flags: 0x10=lat/lon (int32÷1e6), 0x80=name
        /// PHASE4: Decoder liest aktuell float32 bei Offset 36–43 (falsch: erst ab Byte 100 mit Flags).
        case advert         = 0x80  // PACKET_ADVERTISEMENT
        case pathUpdated    = 0x81  // PUSH_PATH_UPDATED — VERIFY: nicht in aktueller Spec
        case sendConfirmed  = 0x82  // PACKET_ACK: [ack_code:6]
        case msgWaiting     = 0x83  // PACKET_MESSAGES_WAITING → CMD_GET_MESSAGE pollen
        case rawData        = 0x84  // VERIFY: nicht in aktueller Spec
        case loginSuccess   = 0x85  // VERIFY: nicht in aktueller Spec
        case loginFail      = 0x86  // VERIFY: nicht in aktueller Spec
        case statusResponse = 0x87  // VERIFY: Spec zeigt 0x88 als PACKET_LOG_DATA; 0x87 unbestätigt
    }

    // MARK: - Fehler-Codes (PACKET_ERROR Byte 1)
    // Quelle: https://docs.meshcore.io/companion_protocol/
    enum ErrorCode: UInt8 {
        case generic            = 0x00
        case invalidCommand     = 0x01
        case invalidParameter   = 0x02
        case channelNotFound    = 0x03
        case channelExists      = 0x04
        case channelOutOfRange  = 0x05
        case secretMismatch     = 0x06
        case messageTooLong     = 0x07
        case deviceBusy         = 0x08
        case insufficientStorage = 0x09
    }

    // MARK: - Grenzen
    /// Maximale Länge einer Textnachricht in UTF-8-Bytes (spec-bestätigt: 133).
    static let maxMessageLength = 133

    /// Maximale Datagram-Payload in Bytes.
    static let maxDatagramPayload = 163

    /// Maximale Kanal-Namenlänge in Bytes (spec: 32B, null-padded).
    static let maxChannelNameLength = 32

    /// Länge des Kanal-Secrets in Bytes (spec: 16B, zeros = öffentlicher Kanal).
    static let channelSecretLength = 16
}

// MARK: - Decoded Frame Typen

/// Strukturiertes Ergebnis nach erfolgreichem Frame-Decode.
enum DecodedFrame: Sendable, Equatable {
    /// Eigene Node-Info (SELF_INFO 0x05).
    /// PHASE4: lat/lon werden aktuell aus float32 gelesen; korrekt wäre int32÷1e6 ab Byte 36.
    case selfInfo(nodeId: String, lat: Double?, lon: Double?, firmware: String)
    case newChannelMessage(MeshMessage)
    case newDirectMessage(MeshMessage)
    case messageAck(messageId: String)
    /// Werbung eines anderen Nodes (ADVERT 0x80, PATH_UPDATED 0x81).
    /// PHASE4: lat/lon kommen erst ab Appdata-Byte 100 mit Flags — werden aktuell falsch gelesen.
    case nodeAdvert(contactId: String, name: String?, lat: Double?, lon: Double?)
    /// Ein Kontakt aus der GET_CONTACTS-Sequenz (CONTACT 0x03).
    case contact(MeshContact)
    case contactsStart
    case contactsEnd
    /// Batterie und Speicher (PACKET_BATTERY 0x0C).
    /// PHASE4: Spec: battery=voltage_mV (16-bit LE), storageUsed/storageFree in KB; aktuell falsch.
    case battAndStorage(battery: Int, storageUsed: Int, storageFree: Int)
    /// RF-Status (Push 0x87).
    case noiseFloor(rssi: Int, noise: Int)
    /// Kanal-Info (PACKET_CHANNEL_INFO 0x12): Name und Secret eines Kanals.
    case channelInfo(index: Int, name: String, secret: Data)
}

// MARK: - Fehler

enum ProtocolError: Error, Equatable, Sendable {
    case emptyFrame
    case unknownCommand(UInt8)
    case invalidPayload(String)
    case messageTooLong(Int)
}

// MARK: - Display

extension DecodedFrame {
    var displayDescription: String {
        switch self {
        case .selfInfo(let nodeId, let lat, _, let firmware):
            let pos = lat.map { String(format: "%.4f", $0) } ?? "-"
            return "SELF_INFO node=\(nodeId) lat=\(pos) fw=\(firmware)"
        case .newChannelMessage(let msg):
            if case .channel(let idx) = msg.kind {
                return "CH_MSG ch=\(idx) hops=\(msg.routing?.hops ?? 0) '\(msg.text.prefix(40))'"
            }
            return "CH_MSG '\(msg.text.prefix(40))'"
        case .newDirectMessage(let msg):
            return "DM from=\(msg.senderName) hops=\(msg.routing?.hops ?? 0) '\(msg.text.prefix(40))'"
        case .messageAck(let id):
            return "ACK id=\(id.prefix(8))"
        case .nodeAdvert(let cid, let name, let lat, _):
            let pos = lat.map { String(format: "%.4f", $0) } ?? "-"
            return "ADVERT id=\(cid) name=\(name ?? "-") lat=\(pos)"
        case .contact(let c):
            return "CONTACT id=\(c.id) name=\(c.name) online=\(c.isOnline)"
        case .contactsStart:
            return "CONTACTS_START"
        case .contactsEnd:
            return "CONTACTS_END"
        case .battAndStorage(let batt, let used, let free):
            return "BATT_STORAGE batt=\(batt)% used=\(used)B free=\(free)B"
        case .noiseFloor(let rssi, let noise):
            return "STATUS rssi=\(rssi)dBm noise=\(noise)dBm"
        case .channelInfo(let idx, let name, _):
            return "CHANNEL_INFO ch=\(idx) name=\(name)"
        }
    }
}
