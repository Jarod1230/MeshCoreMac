# MeshCoreMac Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS App, die sich per BLE mit einem MeshCore-Node verbindet und einen vollständigen Messenger mit Kanal/DM-Support, Tech-Badges, SQLite-Persistenz und Menüleisten-Integration bietet.

**Architecture:** SwiftUI MVVM — `@Observable` ViewModels konsumieren einen BLE-Service (Swift Actor über `AsyncStream<Data>`) und eine GRDB-SQLite-Persistenzschicht. Fehler fließen immer sichtbar zum Nutzer (Banner, Dialoge). Die App wechselt die `NSApplication.ActivationPolicy` je nach Fensterzustand.

**Tech Stack:** Swift 6, SwiftUI, CoreBluetooth, GRDB 6.x, XCTest, xcodegen, macOS 26 (Tahoe)

---

## File Map

### Neue Dateien

**Project Scaffolding**
- `project.yml` — xcodegen-Projektspec
- `MeshCoreMac/Info.plist` — App-Metadaten, Bluetooth-Nutzungsstring
- `MeshCoreMacTests/MeshCoreMacTests.swift` — Test-Einstiegspunkt

**Models** (reine Datenschichten, keine Framework-Imports)
- `MeshCoreMac/Models/ConnectionState.swift`
- `MeshCoreMac/Models/MeshChannel.swift`
- `MeshCoreMac/Models/MeshContact.swift`
- `MeshCoreMac/Models/MeshMessage.swift`

**Protocol Layer** (BLE-Frame encode/decode)
- `MeshCoreMac/Services/MeshCoreProtocol.swift` — Konstanten, Frametypen
- `MeshCoreMac/Services/MeshCoreProtocolService.swift` — Encode/Decode-Logik

**Persistence**
- `MeshCoreMac/Services/MessageStore.swift` — GRDB-Datenbank, Migrations, Queries
- `MeshCoreMac/Services/MessageStoreRecord.swift` — GRDB-Record-Typen (getrennt vom Domain-Modell)

**BLE Service**
- `MeshCoreMac/Services/BluetoothServiceProtocol.swift` — Protokoll für Testbarkeit
- `MeshCoreMac/Services/MeshCoreBluetoothService.swift` — CoreBluetooth-Implementierung

**ViewModels**
- `MeshCoreMac/ViewModels/ConnectionViewModel.swift`
- `MeshCoreMac/ViewModels/SidebarViewModel.swift`
- `MeshCoreMac/ViewModels/ChatViewModel.swift`

**App Infrastructure**
- `MeshCoreMac/App/MeshCoreMacApp.swift` — @main, Window + MenuBar-Scene
- `MeshCoreMac/App/AppDelegate.swift` — Activation Policy Switching
- `MeshCoreMac/App/NotificationService.swift` — UserNotifications-Bridge
- `MeshCoreMac/App/AppContainer.swift` — Dependency-Container (Services + ViewModels)

**Views**
- `MeshCoreMac/Views/MenuBar/MenuBarView.swift`
- `MeshCoreMac/Views/Onboarding/PairingView.swift`
- `MeshCoreMac/Views/MainWindow/MainWindowView.swift`
- `MeshCoreMac/Views/MainWindow/SidebarView.swift`
- `MeshCoreMac/Views/MainWindow/ChatView.swift`
- `MeshCoreMac/Views/MainWindow/MessageBubbleView.swift`
- `MeshCoreMac/Views/Shared/ErrorBannerView.swift`
- `MeshCoreMac/Views/Settings/SettingsView.swift`

**Tests**
- `MeshCoreMacTests/Models/MeshMessageTests.swift`
- `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift`
- `MeshCoreMacTests/Services/MessageStoreTests.swift`
- `MeshCoreMacTests/Services/MockBluetoothService.swift`
- `MeshCoreMacTests/ViewModels/ChatViewModelTests.swift`
- `MeshCoreMacTests/ViewModels/ConnectionViewModelTests.swift`

---

## Task 1: Project Bootstrap (xcodegen)

**Files:**
- Create: `project.yml`
- Create: `MeshCoreMac/App/MeshCoreMacApp.swift` (Skeleton)
- Create: `MeshCoreMacTests/MeshCoreMacTests.swift` (Skeleton)

- [ ] **Step 1: xcodegen installieren**

```bash
brew install xcodegen
xcodegen --version
```

Expected: `XcodeGen Version X.Y.Z`

- [ ] **Step 2: Verzeichnisstruktur anlegen**

```bash
mkdir -p MeshCoreMac/{App,Services,ViewModels,Models,Resources}
mkdir -p MeshCoreMac/Views/{MenuBar,Onboarding,MainWindow,Shared,Settings}
mkdir -p MeshCoreMacTests/{Models,Services,ViewModels}
```

- [ ] **Step 3: project.yml erstellen**

```yaml
name: MeshCoreMac
options:
  bundleIdPrefix: de.Jarod1230
  createIntermediateGroups: true
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: 6.0.0
targets:
  MeshCoreMac:
    type: application
    platform: macOS
    deploymentTarget: "15.0"
    sources:
      - MeshCoreMac
    info:
      path: MeshCoreMac/Info.plist
      properties:
        CFBundleName: MeshCoreMac
        CFBundleDisplayName: MeshCoreMac
        CFBundleIdentifier: de.Jarod1230.meshcoremac
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        NSBluetoothAlwaysUsageDescription: "MeshCoreMac verbindet sich per Bluetooth mit deinem MeshCore-Node."
        LSUIElement: false
    settings:
      base:
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "15.0"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: "NO"
        ENABLE_HARDENED_RUNTIME: "NO"
    dependencies:
      - package: GRDB
        product: GRDB
  MeshCoreMacTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "15.0"
    sources:
      - MeshCoreMacTests
    dependencies:
      - target: MeshCoreMac
    settings:
      base:
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "15.0"
```

> Hinweis: `deploymentTarget: "15.0"` ist der Build-Minimum; macOS 26-spezifische Features werden mit `if #available(macOS 26, *)` gesichert. Sobald Xcode macOS 26 als SDK-Target unterstützt, kann dieser Wert angepasst werden.

- [ ] **Step 4: Minimales App-Entry erstellen**

```swift
// MeshCoreMac/App/MeshCoreMacApp.swift
import SwiftUI

@main
struct MeshCoreMacApp: App {
    var body: some Scene {
        WindowGroup {
            Text("MeshCoreMac wird gestartet…")
        }
    }
}
```

- [ ] **Step 5: Test-Skeleton erstellen**

```swift
// MeshCoreMacTests/MeshCoreMacTests.swift
import XCTest
@testable import MeshCoreMac

final class MeshCoreMacTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Xcode-Projekt generieren**

```bash
xcodegen generate
```

Expected: `✅ Done` und `MeshCoreMac.xcodeproj` im aktuellen Verzeichnis.

- [ ] **Step 7: Build verifizieren**

```bash
xcodebuild -project MeshCoreMac.xcodeproj \
  -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Tests verifizieren**

```bash
xcodebuild -project MeshCoreMac.xcodeproj \
  -scheme MeshCoreMacTests \
  -destination 'platform=macOS' \
  test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add project.yml MeshCoreMac/ MeshCoreMacTests/ MeshCoreMac.xcodeproj/
git commit -m "feat: bootstrap MeshCoreMac Xcode project via xcodegen"
```

---

## Task 2: Data Models

**Files:**
- Create: `MeshCoreMac/Models/ConnectionState.swift`
- Create: `MeshCoreMac/Models/MeshChannel.swift`
- Create: `MeshCoreMac/Models/MeshContact.swift`
- Create: `MeshCoreMac/Models/MeshMessage.swift`
- Create: `MeshCoreMacTests/Models/MeshMessageTests.swift`

- [ ] **Step 1: Failing Tests schreiben**

```swift
// MeshCoreMacTests/Models/MeshMessageTests.swift
import XCTest
@testable import MeshCoreMac

final class MeshMessageTests: XCTestCase {

    func testChannelMessage_hasChannelIndex_noContactId() {
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Node-42",
            text: "Hallo Mesh",
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: 2, snr: -8.5, routeDisplay: "via R-7"),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        guard case .channel(let idx) = msg.kind else {
            return XCTFail("Expected channel message")
        }
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(msg.routing?.hops, 2)
        XCTAssertEqual(msg.routing?.snr, -8.5, accuracy: 0.001)
        XCTAssertEqual(msg.routing?.routeDisplay, "via R-7")
    }

    func testDirectMessage_hasContactId_noChannelIndex() {
        let msg = MeshMessage(
            id: UUID(),
            kind: .direct(contactId: "abc123"),
            senderName: "Node-42",
            text: "Privat",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sent,
            isIncoming: false
        )
        guard case .direct(let cid) = msg.kind else {
            return XCTFail("Expected direct message")
        }
        XCTAssertEqual(cid, "abc123")
    }

    func testDeliveryStatus_transitions() {
        var msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Me",
            text: "Test",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sending,
            isIncoming: false
        )
        XCTAssertEqual(msg.deliveryStatus, .sending)
        msg.deliveryStatus = .delivered
        XCTAssertEqual(msg.deliveryStatus, .delivered)
    }

    func testConnectionState_displayName_ready() {
        let state = ConnectionState.ready(peripheralName: "Node-42")
        XCTAssertEqual(state.displayName, "Bereit: Node-42")
        XCTAssertTrue(state.isReady)
    }

    func testConnectionState_displayName_disconnected() {
        let state = ConnectionState.disconnected
        XCTAssertFalse(state.isReady)
    }
}
```

- [ ] **Step 2: Tests laufen lassen — Fehler bestätigen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | grep -E "(error:|FAILED|succeeded)"
```

Expected: Compile-Fehler — `MeshMessage`, `ConnectionState` nicht definiert.

- [ ] **Step 3: ConnectionState.swift erstellen**

```swift
// MeshCoreMac/Models/ConnectionState.swift
enum ConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting(peripheralName: String)
    case connected(peripheralName: String)
    case ready(peripheralName: String)
    case failed(peripheralName: String, error: String)

    var displayName: String {
        switch self {
        case .disconnected:                    return "Getrennt"
        case .scanning:                        return "Suche Node…"
        case .connecting(let name):            return "Verbinde \(name)…"
        case .connected(let name):             return "Verbunden: \(name)"
        case .ready(let name):                 return "Bereit: \(name)"
        case .failed(_, let err):              return "Fehler: \(err)"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isConnectedOrReady: Bool {
        switch self {
        case .connected, .ready: return true
        default: return false
        }
    }
}
```

- [ ] **Step 4: MeshChannel.swift erstellen**

```swift
// MeshCoreMac/Models/MeshChannel.swift
struct MeshChannel: Identifiable, Hashable, Sendable {
    let id: Int       // Kanal-Index (0-basiert, wie im MeshCore-Protokoll)
    let name: String
}
```

- [ ] **Step 5: MeshContact.swift erstellen**

```swift
// MeshCoreMac/Models/MeshContact.swift
struct MeshContact: Identifiable, Hashable, Sendable {
    let id: String     // Hex-Node-Adresse aus MeshCore (z.B. "a1b2c3d4")
    var name: String
    var lastSeen: Date?
    var isOnline: Bool
}
```

- [ ] **Step 6: MeshMessage.swift erstellen**

```swift
// MeshCoreMac/Models/MeshMessage.swift
struct MeshMessage: Identifiable, Sendable {
    let id: UUID

    enum Kind: Equatable, Sendable {
        case channel(index: Int)
        case direct(contactId: String)
    }

    struct Routing: Equatable, Sendable {
        var hops: Int
        var snr: Float       // dBm, z.B. -8.5
        var routeDisplay: String?  // z.B. "via R-7"
    }

    enum DeliveryStatus: Equatable, Sendable {
        case sending
        case sent
        case delivered
        case failed(String)
    }

    let kind: Kind
    let senderName: String
    let text: String
    let timestamp: Date
    var routing: Routing?
    var deliveryStatus: DeliveryStatus
    var isIncoming: Bool
}
```

- [ ] **Step 7: Tests laufen lassen — Erfolg bestätigen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MeshCoreMac/Models/ MeshCoreMacTests/Models/
git commit -m "feat: add core data models (MeshMessage, MeshChannel, MeshContact, ConnectionState)"
```

---

## Task 3: MeshCore-Protokoll (Konstanten + Parser)

**Files:**
- Create: `MeshCoreMac/Services/MeshCoreProtocol.swift`
- Create: `MeshCoreMac/Services/MeshCoreProtocolService.swift`
- Create: `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift`

> **WICHTIG:** Die BLE-UUIDs und Command-Bytes müssen gegen das offizielle MeshCore-Projekt abgeglichen werden. In Step 1 wird die aktuelle Quelle gesucht. Der unten stehende Code enthält NUS (Nordic UART Service) als Ausgangspunkt — dieser Standard wird von vielen BLE-Mesh-Geräten verwendet und ist der wahrscheinlichste Kandidat.

- [ ] **Step 1: MeshCore BLE-Protokoll recherchieren**

```bash
# Offizielles MeshCore-Repository nach Protokollkonstanten durchsuchen
# Option A: GitHub-CLI falls installiert
gh api repos/ripplebiz/MeshCore/contents/ 2>/dev/null | head -50

# Option B: WebSearch nach "MeshCore BLE protocol UUID characteristic"
# Suche nach: app BLE service UUID, TX/RX characteristic UUIDs, command byte values
# Quellen: GitHub ripplebiz/MeshCore, companion iOS/Android app source
```

Protokollkonstanten, die gefunden und in `MeshCoreProtocol.swift` eingetragen werden müssen:
- `serviceUUID` — BLE Service UUID des MeshCore-Nodes
- `txCharUUID` — Characteristic für Daten vom App → Node (write)
- `rxCharUUID` — Characteristic für Daten vom Node → App (notify)
- Command-Bytes: `APP_START`, `DEVICE_QUERY`, `SEND_TXT_MSG`
- Response-Bytes: `DEVICE_INFO`, `NEW_MSG`, `MSG_ACK`, `NODE_STATUS`

- [ ] **Step 2: Failing Tests schreiben**

```swift
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
        // Frame muss Command-Byte + Kanal-Byte + UTF8-Text enthalten
        XCTAssertGreaterThan(frame.count, 2)
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.sendTxtMsg.rawValue)
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
        // Baue einen synthetischen NEW_MSG-Frame:
        // [NEW_MSG] [channelIndex] [hops] [snr_byte] [utf8_text...]
        var frameBytes: [UInt8] = [
            MeshCoreProtocol.Response.newMsg.rawValue,
            0x00,   // channelIndex = 0
            0x02,   // hops = 2
            0xF8,   // snr raw (Mapping: verify gegen MeshCore-Spec, Beispiel: -8 dBm)
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
```

- [ ] **Step 3: Tests laufen lassen — Fehler bestätigen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | grep -E "(error:|FAILED)"
```

Expected: Compile-Fehler — `MeshCoreProtocol`, `MeshCoreProtocolService` nicht definiert.

- [ ] **Step 4: MeshCoreProtocol.swift erstellen**

> **BYTE-WERTE VERIFIZIEREN:** Die untenstehenden Hex-Werte müssen gegen die MeshCore-Quellen (Step 1) abgeglichen und angepasst werden.

```swift
// MeshCoreMac/Services/MeshCoreProtocol.swift
import CoreBluetooth

enum MeshCoreProtocol {
    // MARK: — BLE UUIDs
    // VERIFIZIEREN gegen MeshCore-Firmware/App-Quellen
    static let serviceUUID  = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // NUS
    static let txCharUUID   = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // write
    static let rxCharUUID   = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // notify

    // MARK: — Commands (App → Node)
    enum Command: UInt8 {
        case appStart    = 0x01  // VERIFIZIEREN
        case deviceQuery = 0x02  // VERIFIZIEREN
        case sendTxtMsg  = 0x10  // VERIFIZIEREN
    }

    // MARK: — Responses (Node → App)
    enum Response: UInt8 {
        case deviceInfo  = 0x80  // VERIFIZIEREN
        case newMsg      = 0x81  // VERIFIZIEREN
        case msgAck      = 0x82  // VERIFIZIEREN
        case nodeStatus  = 0x83  // VERIFIZIEREN
    }

    // MARK: — Grenzen
    static let maxMessageLength = 133  // MeshCore-Protokollgrenze in Bytes (UTF-8)
}

// Decoded Frame Typen
enum DecodedFrame: Sendable {
    case deviceInfo(nodeId: String, firmwareVersion: String)
    case newChannelMessage(MeshMessage)
    case newDirectMessage(MeshMessage)
    case messageAck(messageId: String)
    case nodeStatus(contactId: String, isOnline: Bool)
}

enum ProtocolError: Error {
    case emptyFrame
    case unknownCommand(UInt8)
    case invalidPayload(String)
    case messageTooLong(Int)
}
```

- [ ] **Step 5: MeshCoreProtocolService.swift erstellen**

```swift
// MeshCoreMac/Services/MeshCoreProtocolService.swift
import Foundation

enum MeshCoreProtocolService {

    // MARK: — Encoder

    static func encodeAppStart() -> Data {
        Data([MeshCoreProtocol.Command.appStart.rawValue])
    }

    static func encodeDeviceQuery() -> Data {
        Data([MeshCoreProtocol.Command.deviceQuery.rawValue])
    }

    static func encodeSendTextMessage(
        text: String,
        channelIndex: UInt8,
        recipientId: String?  // nil = Kanal, sonst Hex-ID für DM
    ) throws -> Data {
        guard let textData = text.data(using: .utf8) else {
            throw ProtocolError.invalidPayload("Text nicht als UTF-8 kodierbar")
        }
        guard textData.count <= MeshCoreProtocol.maxMessageLength else {
            throw ProtocolError.messageTooLong(textData.count)
        }
        // Frame: [CMD] [channelIndex] [text_bytes...]
        // Für DMs: recipientId als Präfix im Payload — VERIFIZIEREN gegen MeshCore-Spec
        var frame = Data([MeshCoreProtocol.Command.sendTxtMsg.rawValue, channelIndex])
        frame.append(textData)
        return frame
    }

    // MARK: — Decoder

    static func decodeFrame(_ data: Data) throws -> DecodedFrame {
        guard !data.isEmpty else { throw ProtocolError.emptyFrame }

        let commandByte = data[0]
        let payload = data.dropFirst()

        switch commandByte {
        case MeshCoreProtocol.Response.deviceInfo.rawValue:
            return try decodeDeviceInfo(payload)

        case MeshCoreProtocol.Response.newMsg.rawValue:
            return try decodeNewMessage(payload)

        case MeshCoreProtocol.Response.msgAck.rawValue:
            return try decodeMsgAck(payload)

        case MeshCoreProtocol.Response.nodeStatus.rawValue:
            return try decodeNodeStatus(payload)

        default:
            throw ProtocolError.unknownCommand(commandByte)
        }
    }

    // MARK: — Private Decode Helpers

    private static func decodeDeviceInfo(_ payload: Data) throws -> DecodedFrame {
        // Payload: [nodeId_bytes...][0x00][firmware_bytes...]
        // VERIFIZIEREN gegen MeshCore-Spec — Beispielimplementierung:
        guard payload.count >= 2 else {
            throw ProtocolError.invalidPayload("DEVICE_INFO payload zu kurz")
        }
        let nodeId = payload.prefix(4).map { String(format: "%02x", $0) }.joined()
        let firmware = String(data: payload.dropFirst(4), encoding: .utf8) ?? "unbekannt"
        return .deviceInfo(nodeId: nodeId, firmwareVersion: firmware)
    }

    private static func decodeNewMessage(_ payload: Data) throws -> DecodedFrame {
        // Payload: [channelIndex] [hops] [snr_raw] [text_bytes...]
        // VERIFIZIEREN gegen MeshCore-Spec
        guard payload.count >= 3 else {
            throw ProtocolError.invalidPayload("NEW_MSG payload zu kurz")
        }
        let channelIndex = Int(payload[0])
        let hops = Int(payload[1])
        let snrRaw = Int8(bitPattern: payload[2])
        let snr = Float(snrRaw)  // dBm — Skalierung VERIFIZIEREN
        let textData = payload.dropFirst(3)
        guard let text = String(data: textData, encoding: .utf8) else {
            throw ProtocolError.invalidPayload("Nachrichtentext kein gültiges UTF-8")
        }
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: channelIndex),
            senderName: "Unbekannt",  // Sender-Parsing VERIFIZIEREN gegen Spec
            text: text,
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: hops, snr: snr, routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        return .newChannelMessage(msg)
    }

    private static func decodeMsgAck(_ payload: Data) throws -> DecodedFrame {
        // Payload: [msgId_bytes...] — VERIFIZIEREN gegen MeshCore-Spec
        let msgId = payload.map { String(format: "%02x", $0) }.joined()
        return .messageAck(messageId: msgId)
    }

    private static func decodeNodeStatus(_ payload: Data) throws -> DecodedFrame {
        // Payload: [contactId_bytes][isOnline_byte] — VERIFIZIEREN gegen MeshCore-Spec
        guard payload.count >= 5 else {
            throw ProtocolError.invalidPayload("NODE_STATUS payload zu kurz")
        }
        let contactId = payload.prefix(4).map { String(format: "%02x", $0) }.joined()
        let isOnline = payload[4] != 0
        return .nodeStatus(contactId: contactId, isOnline: isOnline)
    }
}
```

- [ ] **Step 6: Tests anpassen (SNR-Mapping)**

In `MeshCoreProtocolServiceTests.swift`, Zeile mit `0xF8` (SNR raw): Ersetze den Kommentar durch den tatsächlichen SNR-Wert, sobald das MeshCore-Mapping aus Step 1 bekannt ist. Test-Assertion anpassen:

```swift
// Wenn SNR-Mapping aus Spec bekannt (z.B. raw 0xF8 = -8 dBm):
XCTAssertEqual(msg.routing?.snr, -8.0, accuracy: 1.0)
```

- [ ] **Step 7: Tests laufen lassen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MeshCoreMac/Services/MeshCoreProtocol.swift \
        MeshCoreMac/Services/MeshCoreProtocolService.swift \
        MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift
git commit -m "feat: add MeshCore protocol constants and frame parser"
```

---

## Task 4: MessageStore (GRDB SQLite)

**Files:**
- Create: `MeshCoreMac/Services/MessageStoreRecord.swift`
- Create: `MeshCoreMac/Services/MessageStore.swift`
- Create: `MeshCoreMacTests/Services/MessageStoreTests.swift`

- [ ] **Step 1: Failing Tests schreiben**

```swift
// MeshCoreMacTests/Services/MessageStoreTests.swift
import XCTest
import GRDB
@testable import MeshCoreMac

final class MessageStoreTests: XCTestCase {

    var store: MessageStore!

    override func setUp() async throws {
        store = try MessageStore(inMemory: true)
    }

    func testSaveAndFetch_channelMessage() async throws {
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Node-42",
            text: "Hallo",
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: 1, snr: -5.0, routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        try await store.save(msg)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Hallo")
        XCTAssertEqual(fetched[0].routing?.hops, 1)
    }

    func testSaveAndFetch_directMessage() async throws {
        let msg = MeshMessage(
            id: UUID(),
            kind: .direct(contactId: "abc123"),
            senderName: "Node-42",
            text: "Privat",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sent,
            isIncoming: false
        )
        try await store.save(msg)
        let fetched = try await store.fetchMessages(for: .direct(contactId: "abc123"))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Privat")
    }

    func testFetch_returnsOnlyMatchingConversation() async throws {
        let ch0 = MeshMessage(id: UUID(), kind: .channel(index: 0),
            senderName: "A", text: "Kanal 0", timestamp: Date(),
            routing: nil, deliveryStatus: .delivered, isIncoming: true)
        let ch1 = MeshMessage(id: UUID(), kind: .channel(index: 1),
            senderName: "B", text: "Kanal 1", timestamp: Date(),
            routing: nil, deliveryStatus: .delivered, isIncoming: true)
        try await store.save(ch0)
        try await store.save(ch1)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Kanal 0")
    }

    func testUpdateDeliveryStatus() async throws {
        let id = UUID()
        let msg = MeshMessage(id: id, kind: .channel(index: 0),
            senderName: "Me", text: "Test", timestamp: Date(),
            routing: nil, deliveryStatus: .sending, isIncoming: false)
        try await store.save(msg)
        try await store.updateDeliveryStatus(messageId: id, status: .delivered)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched[0].deliveryStatus, .delivered)
    }
}
```

- [ ] **Step 2: Tests laufen lassen — Fehler bestätigen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | grep "error:"
```

Expected: `MessageStore` nicht definiert.

- [ ] **Step 3: MessageStoreRecord.swift erstellen**

```swift
// MeshCoreMac/Services/MessageStoreRecord.swift
import GRDB
import Foundation

// GRDB-Datenbankrecord — getrennt vom Domain-Modell MeshMessage
struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    var id: String           // UUID.uuidString
    var kindType: String     // "channel" | "direct"
    var kindValue: String    // channelIndex als String | contactId
    var senderName: String
    var text: String
    var timestamp: Date
    var hops: Int?
    var snr: Double?
    var routeDisplay: String?
    var deliveryStatusRaw: String  // "sending"|"sent"|"delivered"|"failed:<msg>"
    var isIncoming: Bool

    init(from msg: MeshMessage) {
        self.id = msg.id.uuidString
        switch msg.kind {
        case .channel(let idx):
            self.kindType = "channel"; self.kindValue = String(idx)
        case .direct(let cid):
            self.kindType = "direct"; self.kindValue = cid
        }
        self.senderName = msg.senderName
        self.text = msg.text
        self.timestamp = msg.timestamp
        self.hops = msg.routing.map { Int($0.hops) }
        self.snr = msg.routing.map { Double($0.snr) }
        self.routeDisplay = msg.routing?.routeDisplay
        self.deliveryStatusRaw = msg.deliveryStatus.rawString
        self.isIncoming = msg.isIncoming
    }

    func toMeshMessage() -> MeshMessage {
        let kind: MeshMessage.Kind = kindType == "channel"
            ? .channel(index: Int(kindValue) ?? 0)
            : .direct(contactId: kindValue)
        let routing: MeshMessage.Routing? = hops.map {
            MeshMessage.Routing(hops: $0, snr: Float(snr ?? 0), routeDisplay: routeDisplay)
        }
        return MeshMessage(
            id: UUID(uuidString: id) ?? UUID(),
            kind: kind,
            senderName: senderName,
            text: text,
            timestamp: timestamp,
            routing: routing,
            deliveryStatus: MeshMessage.DeliveryStatus(rawString: deliveryStatusRaw),
            isIncoming: isIncoming
        )
    }
}

// MARK: — DeliveryStatus Serialisierung

extension MeshMessage.DeliveryStatus {
    var rawString: String {
        switch self {
        case .sending:          return "sending"
        case .sent:             return "sent"
        case .delivered:        return "delivered"
        case .failed(let msg):  return "failed:\(msg)"
        }
    }

    init(rawString: String) {
        if rawString.hasPrefix("failed:") {
            self = .failed(String(rawString.dropFirst(7)))
        } else {
            switch rawString {
            case "sending":   self = .sending
            case "sent":      self = .sent
            case "delivered": self = .delivered
            default:          self = .failed("Unbekannter Status")
            }
        }
    }
}
```

- [ ] **Step 4: MessageStore.swift erstellen**

```swift
// MeshCoreMac/Services/MessageStore.swift
import GRDB
import Foundation

final class MessageStore: Sendable {
    private let dbQueue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport
                .appendingPathComponent("MeshCoreMac", isDirectory: true)
                .appendingPathComponent("messages.sqlite")
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            dbQueue = try DatabaseQueue(path: dbURL.path)
        }
        try runMigrations()
    }

    // MARK: — Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_messages") { db in
            try db.create(table: MessageRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kindType", .text).notNull()
                t.column("kindValue", .text).notNull()
                t.column("senderName", .text).notNull()
                t.column("text", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                    .indexed()
                t.column("hops", .integer)
                t.column("snr", .double)
                t.column("routeDisplay", .text)
                t.column("deliveryStatusRaw", .text).notNull()
                t.column("isIncoming", .boolean).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: — Write

    func save(_ message: MeshMessage) async throws {
        let record = MessageRecord(from: message)
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    func updateDeliveryStatus(messageId: UUID, status: MeshMessage.DeliveryStatus) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET deliveryStatusRaw = ? WHERE id = ?",
                arguments: [status.rawString, messageId.uuidString]
            )
        }
    }

    // MARK: — Read

    func fetchMessages(for kind: MeshMessage.Kind, limit: Int = 200) async throws -> [MeshMessage] {
        let (kindType, kindValue): (String, String) = {
            switch kind {
            case .channel(let idx): return ("channel", String(idx))
            case .direct(let cid): return ("direct", cid)
            }
        }()
        return try await dbQueue.read { db in
            let records = try MessageRecord
                .filter(Column("kindType") == kindType && Column("kindValue") == kindValue)
                .order(Column("timestamp").asc)
                .limit(limit)
                .fetchAll(db)
            return records.map { $0.toMeshMessage() }
        }
    }

    // MARK: — Backup / Restore

    var databaseURL: URL? {
        guard let path = dbQueue.path else { return nil }
        return URL(fileURLWithPath: path)
    }

    func exportBackup(to destination: URL) throws {
        guard let srcURL = databaseURL else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: srcURL, to: destination)
    }

    func importBackup(from source: URL) throws {
        guard let destURL = databaseURL else { return }
        // Datenbank kurz schließen und Datei ersetzen — GRDB unterstützt live-replace nicht
        // Daher: Backup-Datei validieren, dann ersetzen
        let testQueue = try DatabaseQueue(path: source.path)
        _ = try testQueue.read { db in try db.tableExists("messages") }
        try FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: source, to: destURL)
    }
}
```

- [ ] **Step 5: Tests laufen lassen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MeshCoreMac/Services/MessageStore.swift \
        MeshCoreMac/Services/MessageStoreRecord.swift \
        MeshCoreMacTests/Services/MessageStoreTests.swift
git commit -m "feat: add GRDB MessageStore with SQLite persistence and backup/restore"
```

---

## Task 5: BLE-Service (Protocol + Implementierung + Mock)

**Files:**
- Create: `MeshCoreMac/Services/BluetoothServiceProtocol.swift`
- Create: `MeshCoreMac/Services/MeshCoreBluetoothService.swift`
- Create: `MeshCoreMacTests/Services/MockBluetoothService.swift`

- [ ] **Step 1: BluetoothServiceProtocol.swift erstellen**

```swift
// MeshCoreMac/Services/BluetoothServiceProtocol.swift
import CoreBluetooth
import Foundation

protocol BluetoothServiceProtocol: AnyObject, Sendable {
    var connectionState: ConnectionState { get }
    var discoveredDevices: [CBPeripheral] { get }
    var incomingFrames: AsyncStream<Data> { get }

    func startScanning()
    func stopScanning()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
    func send(_ data: Data) throws
    func setLastKnownPeripheralId(_ id: UUID?)
}
```

- [ ] **Step 2: MockBluetoothService.swift erstellen (für Tests)**

```swift
// MeshCoreMacTests/Services/MockBluetoothService.swift
import CoreBluetooth
import Foundation
@testable import MeshCoreMac

@Observable
final class MockBluetoothService: BluetoothServiceProtocol {
    var connectionState: ConnectionState = .disconnected
    var discoveredDevices: [CBPeripheral] = []
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation

    var sentFrames: [Data] = []
    var scanStarted = false
    var disconnectCalled = false

    init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
    }

    func startScanning() { scanStarted = true }
    func stopScanning() { scanStarted = false }
    func connect(to peripheral: CBPeripheral) {
        connectionState = .ready(peripheralName: peripheral.name ?? "Mock-Node")
    }
    func disconnect() {
        disconnectCalled = true
        connectionState = .disconnected
    }
    func send(_ data: Data) throws { sentFrames.append(data) }
    func setLastKnownPeripheralId(_ id: UUID?) {}

    // Test-Helper: simuliert eingehenden Frame vom "Node"
    func simulateIncomingFrame(_ data: Data) {
        frameContinuation.yield(data)
    }

    // Test-Helper: simuliert Verbindungsabbruch
    func simulateDisconnect() {
        connectionState = .failed(peripheralName: "Mock-Node", error: "Verbindung verloren")
    }
}
```

- [ ] **Step 3: MeshCoreBluetoothService.swift erstellen**

```swift
// MeshCoreMac/Services/MeshCoreBluetoothService.swift
import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class MeshCoreBluetoothService: NSObject, BluetoothServiceProtocol {

    // MARK: — Observierter Zustand
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredDevices: [CBPeripheral] = []

    // MARK: — Async Frame Stream
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation

    // MARK: — CoreBluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?  // app → node (write)
    private var rxCharacteristic: CBCharacteristic?  // node → app (notify)

    // MARK: — Reconnect
    private var lastKnownPeripheralId: UUID?
    private var reconnectTask: Task<Void, Never>?

    override init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func setLastKnownPeripheralId(_ id: UUID?) {
        self.lastKnownPeripheralId = id
        UserDefaults.standard.set(id?.uuidString, forKey: "lastPeripheralId")
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [MeshCoreProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connecting(peripheralName: peripheral.name ?? "Node")
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        reconnectTask?.cancel()
        if let p = connectedPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        connectionState = .disconnected
    }

    func send(_ data: Data) throws {
        guard let peripheral = connectedPeripheral,
              let characteristic = txCharacteristic else {
            throw BluetoothError.notConnected
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    // MARK: — Auto-Reconnect

    private func scheduleReconnect(peripheralName: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await self?.attemptReconnect(peripheralName: peripheralName)
            }
        }
    }

    private func attemptReconnect(peripheralName: String) {
        guard let id = lastKnownPeripheralId else {
            startScanning()
            return
        }
        let known = centralManager.retrievePeripherals(withIdentifiers: [id])
        if let peripheral = known.first {
            connect(to: peripheral)
        } else {
            startScanning()
        }
    }
}

// MARK: — CBCentralManagerDelegate

extension MeshCoreBluetoothService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                if let idStr = UserDefaults.standard.string(forKey: "lastPeripheralId"),
                   let id = UUID(uuidString: idStr) {
                    lastKnownPeripheralId = id
                }
                attemptReconnect(peripheralName: "")
            case .poweredOff:
                connectionState = .failed(peripheralName: "", error: "Bluetooth ausgeschaltet")
            case .unauthorized:
                connectionState = .failed(peripheralName: "", error: "Bluetooth-Berechtigung fehlt")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
            // Auto-connect zu letztem bekanntem Node
            if peripheral.identifier == lastKnownPeripheralId {
                connect(to: peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            connectionState = .connected(peripheralName: peripheral.name ?? "Node")
            peripheral.delegate = self
            peripheral.discoverServices([MeshCoreProtocol.serviceUUID])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let name = peripheral.name ?? "Node"
            connectionState = .failed(
                peripheralName: name,
                error: error?.localizedDescription ?? "Verbindung getrennt"
            )
            scheduleReconnect(peripheralName: name)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let name = peripheral.name ?? "Node"
            connectionState = .failed(
                peripheralName: name,
                error: error?.localizedDescription ?? "Verbindungsaufbau fehlgeschlagen"
            )
            scheduleReconnect(peripheralName: name)
        }
    }
}

// MARK: — CBPeripheralDelegate

extension MeshCoreBluetoothService: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let services = peripheral.services else { return }
            for service in services where service.uuid == MeshCoreProtocol.serviceUUID {
                peripheral.discoverCharacteristics(
                    [MeshCoreProtocol.txCharUUID, MeshCoreProtocol.rxCharUUID],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard error == nil, let chars = service.characteristics else { return }
            for char in chars {
                if char.uuid == MeshCoreProtocol.txCharUUID {
                    txCharacteristic = char
                } else if char.uuid == MeshCoreProtocol.rxCharUUID {
                    rxCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            if txCharacteristic != nil && rxCharacteristic != nil {
                connectionState = .ready(peripheralName: peripheral.name ?? "Node")
                setLastKnownPeripheralId(peripheral.identifier)
                sendInitSequence()
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        MainActor.assumeIsolated {
            frameContinuation.yield(value)
        }
    }

    private func sendInitSequence() {
        try? send(MeshCoreProtocolService.encodeAppStart())
        try? send(MeshCoreProtocolService.encodeDeviceQuery())
    }
}

// MARK: — Fehler

enum BluetoothError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Kein verbundener Node"
        }
    }
}
```

- [ ] **Step 4: Build prüfen (kein automatischer Test möglich ohne Hardware)**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/Services/BluetoothServiceProtocol.swift \
        MeshCoreMac/Services/MeshCoreBluetoothService.swift \
        MeshCoreMacTests/Services/MockBluetoothService.swift
git commit -m "feat: add BLE service with CoreBluetooth, auto-reconnect, AsyncStream"
```

---

## Task 6: ViewModels + Tests

**Files:**
- Create: `MeshCoreMac/ViewModels/ConnectionViewModel.swift`
- Create: `MeshCoreMac/ViewModels/SidebarViewModel.swift`
- Create: `MeshCoreMac/ViewModels/ChatViewModel.swift`
- Create: `MeshCoreMacTests/ViewModels/ConnectionViewModelTests.swift`
- Create: `MeshCoreMacTests/ViewModels/ChatViewModelTests.swift`

- [ ] **Step 1: Failing Tests schreiben**

```swift
// MeshCoreMacTests/ViewModels/ConnectionViewModelTests.swift
import XCTest
@testable import MeshCoreMac

@MainActor
final class ConnectionViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var vm: ConnectionViewModel!

    override func setUp() {
        mockBluetooth = MockBluetoothService()
        vm = ConnectionViewModel(bluetoothService: mockBluetooth)
    }

    func testInitialState_isDisconnected() {
        XCTAssertEqual(vm.connectionState, .disconnected)
        XCTAssertFalse(vm.isConnected)
    }

    func testStartScan_callsServiceStartScanning() {
        vm.startScan()
        XCTAssertTrue(mockBluetooth.scanStarted)
    }

    func testDisconnect_callsServiceDisconnect() {
        vm.disconnect()
        XCTAssertTrue(mockBluetooth.disconnectCalled)
    }
}

// MeshCoreMacTests/ViewModels/ChatViewModelTests.swift
import XCTest
@testable import MeshCoreMac

@MainActor
final class ChatViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var store: MessageStore!
    var vm: ChatViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        store = try MessageStore(inMemory: true)
        vm = ChatViewModel(
            bluetoothService: mockBluetooth,
            messageStore: store,
            conversation: .channel(index: 0)
        )
    }

    func testSendMessage_encodesAndSendsFrame() async throws {
        try await vm.send(text: "Hallo")
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        let frame = mockBluetooth.sentFrames[0]
        XCTAssertEqual(frame[0], MeshCoreProtocol.Command.sendTxtMsg.rawValue)
    }

    func testSendMessage_savesToStore() async throws {
        try await vm.send(text: "Hallo")
        let msgs = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].text, "Hallo")
        XCTAssertEqual(msgs[0].deliveryStatus, .sending)
    }

    func testSendMessage_rejectsOverlongText() async throws {
        let longText = String(repeating: "A", count: 134)
        do {
            try await vm.send(text: longText)
            XCTFail("Hätte Fehler werfen sollen")
        } catch ProtocolError.messageTooLong {
            // erwartet
        }
    }

    func testIncomingFrame_appearsInMessages() async throws {
        await vm.loadMessages()
        var frameBytes: [UInt8] = [
            MeshCoreProtocol.Response.newMsg.rawValue,
            0x00, 0x01, 0xF8
        ]
        frameBytes += Array("Incoming".utf8)
        mockBluetooth.simulateIncomingFrame(Data(frameBytes))
        // Kurz warten, damit der AsyncStream-Task läuft
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(vm.messages.isEmpty)
    }
}
```

- [ ] **Step 2: Tests laufen lassen — Fehler bestätigen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | grep "error:" | head -10
```

Expected: `ConnectionViewModel`, `ChatViewModel` nicht definiert.

- [ ] **Step 3: ConnectionViewModel.swift erstellen**

```swift
// MeshCoreMac/ViewModels/ConnectionViewModel.swift
import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
final class ConnectionViewModel {
    private let bluetoothService: any BluetoothServiceProtocol

    var connectionState: ConnectionState { bluetoothService.connectionState }
    var discoveredDevices: [CBPeripheral] { bluetoothService.discoveredDevices }

    var isConnected: Bool { connectionState.isConnectedOrReady }
    var errorMessage: String? = nil

    init(bluetoothService: any BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
    }

    func startScan() {
        bluetoothService.startScanning()
    }

    func connect(to peripheral: CBPeripheral) {
        bluetoothService.connect(to: peripheral)
    }

    func disconnect() {
        bluetoothService.disconnect()
    }
}
```

- [ ] **Step 4: SidebarViewModel.swift erstellen**

```swift
// MeshCoreMac/ViewModels/SidebarViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class SidebarViewModel {
    var channels: [MeshChannel] = []
    var contacts: [MeshContact] = []
    var selectedConversation: MeshMessage.Kind? = nil

    private let messageStore: MessageStore

    init(messageStore: MessageStore) {
        self.messageStore = messageStore
        loadDefaultChannels()
    }

    private func loadDefaultChannels() {
        // Kanäle werden beim APP_START / DEVICE_QUERY vom Node befüllt
        // Default: Kanal 0 "Allgemein" als Platzhalter
        channels = [MeshChannel(id: 0, name: "Allgemein")]
    }

    func addChannel(_ channel: MeshChannel) {
        if !channels.contains(channel) {
            channels.append(channel)
        }
    }

    func updateContact(_ contact: MeshContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
    }

    func selectConversation(_ kind: MeshMessage.Kind) {
        selectedConversation = kind
    }
}
```

- [ ] **Step 5: ChatViewModel.swift erstellen**

```swift
// MeshCoreMac/ViewModels/ChatViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private let bluetoothService: any BluetoothServiceProtocol
    private let messageStore: MessageStore

    let conversation: MeshMessage.Kind
    private(set) var messages: [MeshMessage] = []
    var errorMessage: String? = nil
    var inputText: String = ""

    private var listenerTask: Task<Void, Never>?

    init(
        bluetoothService: any BluetoothServiceProtocol,
        messageStore: MessageStore,
        conversation: MeshMessage.Kind
    ) {
        self.bluetoothService = bluetoothService
        self.messageStore = messageStore
        self.conversation = conversation
    }

    func loadMessages() async {
        do {
            messages = try await messageStore.fetchMessages(for: conversation)
        } catch {
            errorMessage = "Nachrichten konnten nicht geladen werden: \(error.localizedDescription)"
        }
        startListening()
    }

    func send(text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let channelIndex: UInt8
        let contactId: String?
        switch conversation {
        case .channel(let idx): channelIndex = UInt8(idx); contactId = nil
        case .direct(let cid):  channelIndex = 0;           contactId = cid
        }

        let frame = try MeshCoreProtocolService.encodeSendTextMessage(
            text: text, channelIndex: channelIndex, recipientId: contactId
        )
        try bluetoothService.send(frame)

        let msg = MeshMessage(
            id: UUID(),
            kind: conversation,
            senderName: "Ich",
            text: text,
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sending,
            isIncoming: false
        )
        messages.append(msg)
        try await messageStore.save(msg)
        inputText = ""
    }

    // MARK: — Incoming Frame Listener

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await frameData in bluetoothService.incomingFrames {
                guard !Task.isCancelled else { break }
                await self.handleFrame(frameData)
            }
        }
    }

    private func handleFrame(_ data: Data) async {
        do {
            let decoded = try MeshCoreProtocolService.decodeFrame(data)
            switch decoded {
            case .newChannelMessage(let msg):
                guard case .channel(let idx) = msg.kind,
                      case .channel(let ours) = conversation,
                      idx == ours else { return }
                messages.append(msg)
                try await messageStore.save(msg)

            case .newDirectMessage(let msg):
                guard case .direct(let cid) = msg.kind,
                      case .direct(let ours) = conversation,
                      cid == ours else { return }
                messages.append(msg)
                try await messageStore.save(msg)

            case .messageAck(let msgId):
                if let idx = messages.firstIndex(where: { $0.id.uuidString == msgId }) {
                    messages[idx].deliveryStatus = .delivered
                    try await messageStore.updateDeliveryStatus(
                        messageId: messages[idx].id, status: .delivered
                    )
                }

            default:
                break
            }
        } catch {
            // Protokoll-Fehler gehen in den Diagnose-Log (Task 12)
        }
    }

    deinit {
        listenerTask?.cancel()
    }
}
```

- [ ] **Step 6: Tests laufen lassen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MeshCoreMac/ViewModels/ MeshCoreMacTests/ViewModels/
git commit -m "feat: add ConnectionViewModel, SidebarViewModel, ChatViewModel with tests"
```

---

## Task 7: App Infrastructure (Entry + AppDelegate + Container)

**Files:**
- Modify: `MeshCoreMac/App/MeshCoreMacApp.swift`
- Create: `MeshCoreMac/App/AppDelegate.swift`
- Create: `MeshCoreMac/App/AppContainer.swift`
- Create: `MeshCoreMac/App/NotificationService.swift`

- [ ] **Step 1: AppContainer.swift erstellen**

```swift
// MeshCoreMac/App/AppContainer.swift
import Foundation

// Zentraler Dependency-Container — alle Services und ViewModels leben hier
@MainActor
final class AppContainer {
    let bluetoothService: MeshCoreBluetoothService
    let messageStore: MessageStore
    let connectionViewModel: ConnectionViewModel
    let sidebarViewModel: SidebarViewModel
    let notificationService: NotificationService

    init() throws {
        bluetoothService = MeshCoreBluetoothService()
        messageStore = try MessageStore()
        connectionViewModel = ConnectionViewModel(bluetoothService: bluetoothService)
        sidebarViewModel = SidebarViewModel(messageStore: messageStore)
        notificationService = NotificationService()
    }

    func makeChatViewModel(for conversation: MeshMessage.Kind) -> ChatViewModel {
        ChatViewModel(
            bluetoothService: bluetoothService,
            messageStore: messageStore,
            conversation: conversation
        )
    }
}
```

- [ ] **Step 2: AppDelegate.swift erstellen**

```swift
// MeshCoreMac/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Activation Policy: Dock-Icon nur wenn Fenster offen
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // App läuft weiter als Menüleisten-App
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    // Wird vom WindowObserver aufgerufen, wenn das letzte Fenster geschlossen wird
    func switchToAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
    }
}
```

- [ ] **Step 3: NotificationService.swift erstellen**

```swift
// MeshCoreMac/App/NotificationService.swift
import UserNotifications
import Foundation

final class NotificationService: Sendable {

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    func sendNewMessageNotification(senderName: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = preview
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // sofort
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: MeshCoreMacApp.swift vollständig ersetzen**

```swift
// MeshCoreMac/App/MeshCoreMacApp.swift
import SwiftUI

@main
struct MeshCoreMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let container: AppContainer

    init() {
        do {
            container = try AppContainer()
            container.notificationService.requestPermission()
        } catch {
            fatalError("AppContainer-Initialisierung fehlgeschlagen: \(error)")
        }
    }

    var body: some Scene {
        // Hauptfenster
        WindowGroup {
            MainWindowView(container: container)
                .onDisappear {
                    appDelegate.switchToAccessoryMode()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}  // "Neu"-Menü entfernen
        }

        // Menüleiste
        MenuBarExtra("MeshCoreMac", systemImage: menuBarIcon) {
            MenuBarView(
                container: container,
                openWindow: openMainWindow
            )
        }
    }

    private var menuBarIcon: String {
        switch container.connectionViewModel.connectionState {
        case .ready:                           return "antenna.radiowaves.left.and.right.circle.fill"
        case .scanning, .connecting, .connected: return "antenna.radiowaves.left.and.right.circle"
        default:                               return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 5: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MeshCoreMac/App/
git commit -m "feat: add AppContainer, AppDelegate, NotificationService, app entry point"
```

---

## Task 8: MenuBar

**Files:**
- Create: `MeshCoreMac/Views/MenuBar/MenuBarView.swift`

- [ ] **Step 1: MenuBarView.swift erstellen**

```swift
// MeshCoreMac/Views/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let container: AppContainer
    let openWindow: () -> Void

    var body: some View {
        let state = container.connectionViewModel.connectionState

        // Status-Zeile
        Label(state.displayName, systemImage: statusIcon(for: state))
            .foregroundStyle(statusColor(for: state))

        Divider()

        // Letzte Nachrichten (Platzhalter — wird in Task 10 mit echten Daten gefüllt)
        Text("Keine neuen Nachrichten")
            .foregroundStyle(.secondary)

        Divider()

        Button("Fenster öffnen") { openWindow() }

        Button("Verbindung trennen") {
            container.connectionViewModel.disconnect()
        }
        .disabled(!container.connectionViewModel.isConnected)

        Divider()

        Button("MeshCoreMac beenden") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func statusIcon(for state: ConnectionState) -> String {
        switch state {
        case .ready:                               return "circle.fill"
        case .scanning, .connecting, .connected:   return "circle.dotted"
        default:                                   return "circle.slash"
        }
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .ready:                               return .green
        case .scanning, .connecting, .connected:   return .yellow
        default:                                   return .red
        }
    }
}
```

- [ ] **Step 2: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MeshCoreMac/Views/MenuBar/MenuBarView.swift
git commit -m "feat: add menu bar view with connection status and actions"
```

---

## Task 9: Pairing View (BLE-Gerätewahl)

**Files:**
- Create: `MeshCoreMac/Views/Onboarding/PairingView.swift`

- [ ] **Step 1: PairingView.swift erstellen**

```swift
// MeshCoreMac/Views/Onboarding/PairingView.swift
import SwiftUI
import CoreBluetooth

struct PairingView: View {
    let connectionVM: ConnectionViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("MeshCore-Node verbinden")
                .font(.title2.bold())

            Text("Scanne nach MeshCore-Nodes in der Nähe und wähle deinen Node aus.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if connectionVM.discoveredDevices.isEmpty {
                ContentUnavailableView(
                    "Keine Nodes gefunden",
                    systemImage: "magnifyingglass",
                    description: Text("Stelle sicher, dass dein MeshCore-Node eingeschaltet ist.")
                )
            } else {
                List(connectionVM.discoveredDevices, id: \.identifier) { peripheral in
                    Button {
                        connectionVM.connect(to: peripheral)
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text(peripheral.name ?? "Unbekannter Node")
                            Spacer()
                            Text(peripheral.identifier.uuidString.prefix(8) + "…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 150)
            }

            HStack(spacing: 12) {
                Button {
                    connectionVM.startScan()
                } label: {
                    Label("Suchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                if case .scanning = connectionVM.connectionState {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 350)
        .onAppear { connectionVM.startScan() }
    }
}
```

- [ ] **Step 2: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MeshCoreMac/Views/Onboarding/PairingView.swift
git commit -m "feat: add BLE pairing view with device discovery list"
```

---

## Task 10: Main Window + Sidebar

**Files:**
- Create: `MeshCoreMac/Views/MainWindow/MainWindowView.swift`
- Create: `MeshCoreMac/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: SidebarView.swift erstellen**

```swift
// MeshCoreMac/Views/MainWindow/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    let sidebarVM: SidebarViewModel
    let connectionVM: ConnectionViewModel

    var body: some View {
        List(selection: Binding(
            get: { sidebarVM.selectedConversation.map(ConversationID.init) },
            set: { id in
                if let kind = id?.kind { sidebarVM.selectConversation(kind) }
            }
        )) {
            // Kanäle
            Section("Kanäle") {
                ForEach(sidebarVM.channels) { channel in
                    Label("# \(channel.name)", systemImage: "number")
                        .tag(ConversationID(kind: .channel(index: channel.id)))
                }
            }

            // Direktnachrichten
            if !sidebarVM.contacts.isEmpty {
                Section("Direkt") {
                    ForEach(sidebarVM.contacts) { contact in
                        HStack {
                            Label(contact.name, systemImage: "person.fill")
                            Spacer()
                            Circle()
                                .fill(contact.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                        }
                        .tag(ConversationID(kind: .direct(contactId: contact.id)))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // Verbindungsstatus unten in der Sidebar
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionVM.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(connectionVM.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// Wrapper für Hashable-Konformität in List(selection:)
struct ConversationID: Hashable {
    let kind: MeshMessage.Kind
}
```

- [ ] **Step 2: MainWindowView.swift erstellen**

```swift
// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    var body: some View {
        Group {
            if container.connectionViewModel.isConnected {
                messengerView
            } else {
                PairingView(connectionVM: container.connectionViewModel)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var messengerView: some View {
        NavigationSplitView {
            SidebarView(
                sidebarVM: container.sidebarViewModel,
                connectionVM: container.connectionViewModel
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let conversation = container.sidebarViewModel.selectedConversation {
                ChatView(
                    chatVM: container.makeChatViewModel(for: conversation),
                    conversation: conversation
                )
            } else {
                ContentUnavailableView(
                    "Keine Konversation gewählt",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Wähle einen Kanal oder Kontakt in der Sidebar.")
                )
            }
        }
    }
}
```

- [ ] **Step 3: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MeshCoreMac/Views/MainWindow/MainWindowView.swift \
        MeshCoreMac/Views/MainWindow/SidebarView.swift
git commit -m "feat: add main window with NavigationSplitView, sidebar, pairing handoff"
```

---

## Task 11: Chat View (Nachrichten + Tech-Badges + Eingabe)

**Files:**
- Create: `MeshCoreMac/Views/MainWindow/MessageBubbleView.swift`
- Create: `MeshCoreMac/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: MessageBubbleView.swift erstellen**

```swift
// MeshCoreMac/Views/MainWindow/MessageBubbleView.swift
import SwiftUI

struct MessageBubbleView: View {
    let message: MeshMessage

    var body: some View {
        VStack(alignment: message.isIncoming ? .leading : .trailing, spacing: 4) {
            // Absender + Zeitstempel
            HStack(spacing: 4) {
                if message.isIncoming {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Nachrichtenblase
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.isIncoming ? Color(.controlBackgroundColor) : Color.accentColor)
                .foregroundStyle(message.isIncoming ? Color.primary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Tech-Badges (Hops / SNR / Route)
            if let routing = message.routing {
                HStack(spacing: 6) {
                    Label("\(routing.hops) Hops", systemImage: "arrow.triangle.swap")
                    Label(String(format: "SNR %.0f dBm", routing.snr), systemImage: "waveform")
                    if let route = routing.routeDisplay {
                        Label(route, systemImage: "arrow.right.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            // Zustellstatus
            deliveryStatusView
        }
        .frame(maxWidth: .infinity, alignment: message.isIncoming ? .leading : .trailing)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        switch message.deliveryStatus {
        case .sending:
            Label("Wird gesendet…", systemImage: "arrow.up.circle")
                .font(.caption2).foregroundStyle(.secondary)
        case .sent:
            Label("Gesendet", systemImage: "checkmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
        case .delivered:
            Label("Zugestellt ✓", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .failed(let reason):
            Label("Nicht zugestellt ⚠️ — \(reason)", systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2: ChatView.swift erstellen**

```swift
// MeshCoreMac/Views/MainWindow/ChatView.swift
import SwiftUI

struct ChatView: View {
    @State var chatVM: ChatViewModel
    let conversation: MeshMessage.Kind

    @State private var sendError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Fehler-Banner (Task 12 erweitert dies)
            if let error = chatVM.errorMessage {
                ErrorBannerView(message: error) { chatVM.errorMessage = nil }
            }

            // Nachrichtenliste
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chatVM.messages) { msg in
                            MessageBubbleView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: chatVM.messages.count) { _, _ in
                    if let last = chatVM.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Eingabefeld
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Nachricht eingeben…", text: $chatVM.inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await trySend() } }

                    // Zeichenzähler
                    let count = chatVM.inputText.utf8.count
                    Text("\(count)/\(MeshCoreProtocol.maxMessageLength)")
                        .font(.caption2)
                        .foregroundStyle(count > MeshCoreProtocol.maxMessageLength ? .red : .tertiary)
                }

                Button {
                    Task { await trySend() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(
                    chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty ||
                    chatVM.inputText.utf8.count > MeshCoreProtocol.maxMessageLength
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .task { await chatVM.loadMessages() }
        .navigationTitle(conversationTitle)
    }

    private var conversationTitle: String {
        switch conversation {
        case .channel(let idx): return "Kanal \(idx)"
        case .direct(let cid):  return cid
        }
    }

    private func trySend() async {
        do {
            try await chatVM.send(text: chatVM.inputText)
        } catch {
            sendError = error.localizedDescription
            chatVM.errorMessage = sendError
        }
    }
}
```

- [ ] **Step 3: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MeshCoreMac/Views/MainWindow/ChatView.swift \
        MeshCoreMac/Views/MainWindow/MessageBubbleView.swift
git commit -m "feat: add ChatView with message bubbles, tech-badges, 133-char input counter"
```

---

## Task 12: Fehlerbehandlung (ErrorBannerView)

**Files:**
- Create: `MeshCoreMac/Views/Shared/ErrorBannerView.swift`

- [ ] **Step 1: ErrorBannerView.swift erstellen**

```swift
// MeshCoreMac/Views/Shared/ErrorBannerView.swift
import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

- [ ] **Step 2: Bluetooth-Fehler in ConnectionViewModel weiterleiten**

In `ConnectionViewModel.swift`, füge eine Beobachtung des BLE-Zustandswechsels zu `.failed` hinzu:

```swift
// In ConnectionViewModel.swift, nach init():
func startObservingErrors() {
    // Fehler aus dem Verbindungszustand ableiten
    // Wird im MainWindowView via .task aufgerufen
}

var currentError: String? {
    if case .failed(_, let error) = connectionState {
        return error
    }
    return nil
}
```

- [ ] **Step 3: ErrorBanner in MainWindowView integrieren**

In `MainWindowView.swift`, füge vor `messengerView` ein:

```swift
// Ersetze die `messengerView`-Referenz in `body`:
Group {
    if container.connectionViewModel.isConnected {
        messengerView
            .overlay(alignment: .top) {
                if let err = container.connectionViewModel.currentError {
                    ErrorBannerView(message: err) {}
                        .animation(.easeInOut, value: err)
                }
            }
    } else {
        PairingView(connectionVM: container.connectionViewModel)
    }
}
```

- [ ] **Step 4: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/Views/Shared/ErrorBannerView.swift MeshCoreMac/ViewModels/ MeshCoreMac/Views/MainWindow/
git commit -m "feat: add ErrorBannerView and wire connection errors to UI"
```

---

## Task 13: Systembenachrichtigungen

**Files:**
- Modify: `MeshCoreMac/ViewModels/ChatViewModel.swift`
- Modify: `MeshCoreMac/App/AppContainer.swift`

- [ ] **Step 1: NotificationService in ChatViewModel integrieren**

In `ChatViewModel.swift`, erweitere den Initializer und `handleFrame`:

```swift
// Ersetze init() in ChatViewModel.swift:
private let notificationService: NotificationService

init(
    bluetoothService: any BluetoothServiceProtocol,
    messageStore: MessageStore,
    conversation: MeshMessage.Kind,
    notificationService: NotificationService
) {
    self.bluetoothService = bluetoothService
    self.messageStore = messageStore
    self.conversation = conversation
    self.notificationService = notificationService
}
```

Dann in `handleFrame`, nach `messages.append(msg)` für eingehende Nachrichten:

```swift
// Nach messages.append(msg) für eingehende Nachrichten:
if msg.isIncoming {
    notificationService.sendNewMessageNotification(
        senderName: msg.senderName,
        preview: String(msg.text.prefix(60))
    )
}
```

- [ ] **Step 2: AppContainer aktualisieren**

In `AppContainer.swift`, `makeChatViewModel` anpassen:

```swift
func makeChatViewModel(for conversation: MeshMessage.Kind) -> ChatViewModel {
    ChatViewModel(
        bluetoothService: bluetoothService,
        messageStore: messageStore,
        conversation: conversation,
        notificationService: notificationService
    )
}
```

- [ ] **Step 3: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Tests aktualisieren** (ChatViewModelTests)

In `ChatViewModelTests.swift`, `setUp` anpassen:

```swift
vm = ChatViewModel(
    bluetoothService: mockBluetooth,
    messageStore: store,
    conversation: .channel(index: 0),
    notificationService: NotificationService()
)
```

- [ ] **Step 5: Tests laufen lassen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MeshCoreMac/ViewModels/ChatViewModel.swift MeshCoreMac/App/AppContainer.swift \
        MeshCoreMacTests/ViewModels/ChatViewModelTests.swift
git commit -m "feat: integrate UserNotifications for incoming messages"
```

---

## Task 14: Backup/Restore (Settings-View)

**Files:**
- Create: `MeshCoreMac/Views/Settings/SettingsView.swift`
- Modify: `MeshCoreMac/App/MeshCoreMacApp.swift`

- [ ] **Step 1: SettingsView.swift erstellen**

```swift
// MeshCoreMac/Views/Settings/SettingsView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let messageStore: MessageStore

    @State private var showExportPanel = false
    @State private var showImportPanel = false
    @State private var statusMessage: String? = nil

    var body: some View {
        Form {
            Section("Daten") {
                Button("Backup erstellen…") { showExportPanel = true }
                Button("Backup wiederherstellen…") { showImportPanel = true }
                    .foregroundStyle(.orange)
            }

            if let status = statusMessage {
                Section {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400)
        .fileExporter(
            isPresented: $showExportPanel,
            document: BackupDocument(store: messageStore),
            contentType: .meshcoreBackup,
            defaultFilename: "MeshCore-Backup-\(formattedDate)"
        ) { result in
            switch result {
            case .success: statusMessage = "Backup erfolgreich erstellt."
            case .failure(let err): statusMessage = "Backup fehlgeschlagen: \(err.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [.meshcoreBackup]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    try messageStore.importBackup(from: url)
                    statusMessage = "Backup erfolgreich wiederhergestellt."
                } catch {
                    statusMessage = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
                }
            case .failure(let err):
                statusMessage = "Fehler beim Öffnen: \(err.localizedDescription)"
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// FileDocument-Wrapper für den Exporter
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.meshcoreBackup] }
    let store: MessageStore

    init(store: MessageStore) { self.store = store }
    init(configuration: ReadConfiguration) throws {
        fatalError("Import wird über fileImporter gehandhabt")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = store.databaseURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return FileWrapper(regularFileWithContents: data)
    }
}

// Custom UTType für .meshcorebackup
extension UTType {
    static let meshcoreBackup = UTType(exportedAs: "de.Jarod1230.meshcoremac.backup")
}
```

- [ ] **Step 2: UTType in Info.plist registrieren**

In `project.yml`, unter `MeshCoreMac > info > properties`:

```yaml
CFBundleDocumentTypes:
  - CFBundleTypeName: MeshCore Backup
    CFBundleTypeRole: Editor
    LSItemContentTypes:
      - de.Jarod1230.meshcoremac.backup
UTExportedTypeDeclarations:
  - UTTypeIdentifier: de.Jarod1230.meshcoremac.backup
    UTTypeDescription: MeshCore Backup
    UTTypeConformsTo:
      - public.data
    UTTypeTagSpecification:
      public.filename-extension:
        - meshcorebackup
```

Nach Änderung: `xcodegen generate` ausführen.

- [ ] **Step 3: Settings-Scene in MeshCoreMacApp.swift hinzufügen**

In `MeshCoreMacApp.swift`, nach der `MenuBarExtra`-Scene:

```swift
Settings {
    SettingsView(messageStore: container.messageStore)
}
```

- [ ] **Step 4: xcodegen neu generieren**

```bash
xcodegen generate
```

- [ ] **Step 5: Build prüfen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Alle Tests laufen lassen**

```bash
xcodebuild -project MeshCoreMac.xcodeproj -scheme MeshCoreMacTests \
  -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Finaler Commit**

```bash
git add MeshCoreMac/Views/Settings/ MeshCoreMac/App/MeshCoreMacApp.swift project.yml
git commit -m "feat: add backup/restore Settings view with .meshcorebackup file type"
```

---

## Abnahmekriterien (aus Spec)

Alle 8 Erfolgskriterien aus der Spec werden durch diese Tasks abgedeckt:

| Kriterium | Tasks |
|---|---|
| BLE-Verbindung zu MeshCore-Node | Task 5 (BLE Service) |
| Kanäle und DMs lesen + senden | Task 6 (ViewModels), Task 11 (ChatView) |
| Tech-Badges (Hops, SNR, Route) | Task 11 (MessageBubbleView) |
| Hintergrundbetrieb + Menüleiste | Task 7 (AppDelegate), Task 8 (MenuBarView) |
| macOS-Benachrichtigungen | Task 13 |
| Persistenz über Neustart | Task 4 (MessageStore) |
| Manuelles Backup/Restore | Task 14 |
| Fehler immer sichtbar | Task 12 (ErrorBannerView) |
