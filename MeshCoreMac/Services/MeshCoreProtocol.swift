// MeshCoreMac/Services/MeshCoreProtocol.swift
//
// MeshCore Companion Radio Protocol
// Quellen:
//   - https://docs.meshcore.io/companion_protocol/
//   - https://github.com/meshcore-dev/MeshCore/wiki/Companion-Radio-Protocol
//
// Stand: Mai 2026. Werte aus offizieller Spec übernommen, sofern verifiziert.
// Bei Unsicherheit ist eine `// VERIFY:` Markierung gesetzt.

import CoreBluetooth
import Foundation

enum MeshCoreProtocol {
    // MARK: - BLE UUIDs (Nordic UART Service Variante)
    // Verifiziert via offizieller MeshCore Companion-Spec.
    // CBUUID ist in Apple's Frameworks nicht als Sendable markiert, ist aber
    // de-facto immutable nach Initialisierung. Daher nonisolated(unsafe).
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    /// App → Node (RX-Char aus Sicht der Firmware = Write-Endpoint).
    nonisolated(unsafe) static let txCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    /// Node → App (TX-Char aus Sicht der Firmware = Notify-Endpoint).
    nonisolated(unsafe) static let rxCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    // MARK: - Commands (App → Node)
    // Verifiziert gegen offizielle Spec (Hex-Werte).
    enum Command: UInt8 {
        case appStart           = 0x01  // CMD_APP_START
        case sendTxtMsg         = 0x02  // CMD_SEND_TXT_MSG (DM)
        case sendChannelTxtMsg  = 0x03  // CMD_SEND_CHANNEL_TXT_MSG
        case getContacts        = 0x04  // CMD_GET_CONTACTS
        case getDeviceTime      = 0x05  // CMD_GET_DEVICE_TIME
        case syncNextMessage    = 0x0A  // CMD_SYNC_NEXT_MESSAGE
        case getBattAndStorage  = 0x14  // CMD_GET_BATT_AND_STORAGE
        case deviceQuery        = 0x16  // CMD_DEVICE_QUERY (22)
    }

    // MARK: - Responses (Node → App, synchron auf Command)
    // Verifiziert gegen offizielle Spec.
    enum Response: UInt8 {
        case ok                = 0x00  // RESP_CODE_OK
        case err               = 0x01  // RESP_CODE_ERR
        case contactsStart     = 0x02
        case contact           = 0x03
        case endOfContacts     = 0x04
        case selfInfo          = 0x05  // RESP_CODE_SELF_INFO (DEVICE_INFO Äquivalent)
        case sent              = 0x06
        case contactMsgRecv    = 0x07  // RESP_CODE_CONTACT_MSG_RECV
        case channelMsgRecv    = 0x08  // RESP_CODE_CHANNEL_MSG_RECV
        case currTime          = 0x09
        case noMoreMessages    = 0x0A
        case battAndStorage    = 0x0C
        case deviceInfo        = 0x0D  // RESP_CODE_DEVICE_INFO

        // Plan-Aliase (verwendet von den Tests in TDD-Spec):
        // newMsg ist im Test-Plan ein synthetischer Frame-Typ; wir mappen ihn
        // auf channelMsgRecv, da das semantisch dem entspricht.
        // VERIFY: Echtes V3-Frame-Format weicht ab; siehe DecodedFrame.
        static var newMsg: Response { .channelMsgRecv }
        static var msgAck: Response { .sent }              // Sent-Confirmation
    }

    // MARK: - V3-Responses mit SNR
    // SNR-Skalierung: signed int8 × 0.25 dB (verifiziert).
    enum ResponseV3: UInt8 {
        case contactMsgRecvV3  = 0x10  // RESP_CODE_CONTACT_MSG_RECV_V3
        case channelMsgRecvV3  = 0x11  // RESP_CODE_CHANNEL_MSG_RECV_V3
    }

    // MARK: - Push-Notifications (Node → App, asynchron)
    // Verifiziert; alle haben das hohe Bit (>= 0x80).
    enum Push: UInt8 {
        case advert         = 0x80  // PUSH_CODE_ADVERT
        case pathUpdated    = 0x81  // PUSH_CODE_PATH_UPDATED
        case sendConfirmed  = 0x82  // PUSH_CODE_SEND_CONFIRMED
        case msgWaiting     = 0x83  // PUSH_CODE_MSG_WAITING
        case rawData        = 0x84
        case loginSuccess   = 0x85
        case loginFail      = 0x86
        case statusResponse = 0x87
    }

    // MARK: - Grenzen
    /// Maximale Länge einer Textnachricht in UTF-8-Bytes.
    /// Quelle: MeshCore Companion-Spec (ältere Version: 133, neuere: bis 160).
    /// Wir verwenden den konservativeren Wert für Phase 1.
    /// VERIFY: Bei späteren Firmware-Versionen ggf. auf 160 anheben.
    static let maxMessageLength = 133

    /// Default BLE-MTU (kann auf 512 Bytes erhöht werden).
    static let defaultMTU = 23
    static let maxMTU     = 512
}

// MARK: - Decoded Frame Typen

/// Strukturiertes Ergebnis nach erfolgreichem Frame-Decode.
enum DecodedFrame: Sendable, Equatable {
    /// Eigene Node-Info mit optionaler GPS-Position (SELF_INFO 0x05, DEVICE_INFO 0x0D).
    case selfInfo(nodeId: String, lat: Double?, lon: Double?, firmware: String)
    case newChannelMessage(MeshMessage)
    case newDirectMessage(MeshMessage)
    case messageAck(messageId: String)
    /// Werbung eines anderen Nodes mit optionaler Position (ADVERT 0x80, PATH_UPDATED 0x81).
    case nodeAdvert(contactId: String, name: String?, lat: Double?, lon: Double?)
    /// Ein Kontakt aus der GET_CONTACTS-Antwort-Sequenz (CONTACT 0x03).
    case contact(MeshContact)
    /// Startsignal der GET_CONTACTS-Antwort (CONTACTS_START 0x02).
    case contactsStart
    /// Endsignal der GET_CONTACTS-Antwort (END_OF_CONTACTS 0x04).
    case contactsEnd
}

// MARK: - Fehler

enum ProtocolError: Error, Equatable, Sendable {
    case emptyFrame
    case unknownCommand(UInt8)
    case invalidPayload(String)
    case messageTooLong(Int)
}
