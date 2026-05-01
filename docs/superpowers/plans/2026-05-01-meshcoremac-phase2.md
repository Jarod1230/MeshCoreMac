# MeshCoreMac Phase 2 — Kontakte & Karte

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Contacts persisted from MeshCore protocol events (ADVERT, GET_CONTACTS, SELF_INFO) with editable names, an online/last-seen indicator, and a MapKit map showing node positions.

**Architecture:** ContactStore (GRDB) owns contact persistence. ContactsViewModel subscribes to a new `nodeEventStream: AsyncStream<DecodedFrame>` on BluetoothService, updating in-memory contacts and the store. SidebarView and ChatView read contacts from ContactsViewModel. DecodedFrame gets richer cases that carry lat/lon and contact list data decoded from real MeshCore frames.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI + MVVM + `@Observable`, CoreBluetooth, GRDB 6, MapKit (SwiftUI `Map`), XCTest

---

## Existing Codebase Context

Read these files before starting any task — they define the interfaces every task builds on:

- `MeshCoreMac/Services/MeshCoreProtocol.swift` — DecodedFrame, Command/Response enums
- `MeshCoreMac/Services/BluetoothServiceProtocol.swift` — protocol that MockBluetoothService implements
- `MeshCoreMac/Services/MeshCoreBluetoothService.swift` — BLE service, see `sendInitSequence()` and `didUpdateValueFor`
- `MeshCoreMac/ViewModels/ChatViewModel.swift` — `handleFrame` switch must stay exhaustive over DecodedFrame
- `MeshCoreMac/Views/MainWindow/MainWindowView.swift` — passes `container.*` to SidebarView and ChatView
- `MeshCoreMacTests/Services/MockBluetoothService.swift` — mock used by all ViewModel tests

**Key invariants to preserve:**
- `incomingFrames: AsyncStream<Data>` on BluetoothService stays **unchanged** — ChatViewModel still consumes raw bytes
- All Swift 6 strict concurrency rules: `@MainActor` on ViewModels, `nonisolated(unsafe)` for Task properties in deinit, `@preconcurrency` for CB delegates
- Tests use `XCTest` / `XCTestCase`, `@MainActor` on class, `override func setUp() async throws`
- `nonisolated deinit` pattern: `nonisolated(unsafe) private var listenerTask: Task<Void, Never>?` then `deinit { listenerTask?.cancel() }`

---

## File Structure

```
New files:
  MeshCoreMac/Services/ContactRecord.swift            — GRDB FetchableRecord/PersistableRecord for MeshContact
  MeshCoreMac/Services/ContactStore.swift             — GRDB-backed contact persistence (mirrors MessageStore)
  MeshCoreMac/ViewModels/ContactsViewModel.swift      — @Observable, consumes nodeEventStream, owns contact list
  MeshCoreMac/Views/MainWindow/ContactDetailView.swift — editable name, lat/lon, lastSeen, online badge
  MeshCoreMac/Views/Map/MapView.swift                 — SwiftUI Map with Marker per node
  MeshCoreMacTests/Services/ContactStoreTests.swift
  MeshCoreMacTests/ViewModels/ContactsViewModelTests.swift

Modified files:
  MeshCoreMac/Models/MeshContact.swift                — add lat: Double?, lon: Double?
  MeshCoreMac/Services/MeshCoreProtocol.swift         — rename DecodedFrame cases, add new cases, add encodeGetContacts
  MeshCoreMac/Services/MeshCoreProtocolService.swift  — decode ADVERT/SELF_INFO with position, decode CONTACT list
  MeshCoreMac/Services/BluetoothServiceProtocol.swift — add nodeEventStream
  MeshCoreMac/Services/MeshCoreBluetoothService.swift — add nodeEventStream, routing, send GET_CONTACTS
  MeshCoreMacTests/Services/MockBluetoothService.swift — add nodeEventStream + simulateNodeEvent
  MeshCoreMac/ViewModels/ChatViewModel.swift          — update handleFrame switch for renamed/new DecodedFrame cases
  MeshCoreMac/ViewModels/SidebarViewModel.swift       — remove contacts/updateContact (owned by ContactsViewModel)
  MeshCoreMac/App/AppContainer.swift                  — add contactStore, contactsViewModel
  MeshCoreMac/Views/MainWindow/SidebarView.swift      — use contactsVM.contacts, add contact detail sheet
  MeshCoreMac/Views/MainWindow/ChatView.swift         — add contactsVM param for DM title resolution
  MeshCoreMac/Views/MainWindow/MainWindowView.swift   — pass contactsVM, add Map toolbar button
```

---

## Task 1: Extended MeshContact + ContactRecord + ContactStore

**Files:**
- Modify: `MeshCoreMac/Models/MeshContact.swift`
- Create: `MeshCoreMac/Services/ContactRecord.swift`
- Create: `MeshCoreMac/Services/ContactStore.swift`
- Create: `MeshCoreMacTests/Services/ContactStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MeshCoreMacTests/Services/ContactStoreTests.swift`:

```swift
import XCTest
@testable import MeshCoreMac

@MainActor
final class ContactStoreTests: XCTestCase {

    func testSaveAndFetch_roundtripsAllFields() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "a1b2c3d4", name: "Alice",
                                   lastSeen: nil, isOnline: true,
                                   lat: 48.137, lon: 11.575)
        try await store.save(contact)
        let all = try await store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "a1b2c3d4")
        XCTAssertEqual(all[0].name, "Alice")
        XCTAssertEqual(all[0].isOnline, true)
        XCTAssertEqual(all[0].lat ?? 0, 48.137, accuracy: 0.0001)
        XCTAssertEqual(all[0].lon ?? 0, 11.575, accuracy: 0.0001)
    }

    func testSave_upsertsByPrimaryKey() async throws {
        let store = try ContactStore(inMemory: true)
        var contact = MeshContact(id: "a1b2c3d4", name: "Bob",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        contact.name = "Bob Updated"
        contact.isOnline = true
        contact.lat = 52.52
        contact.lon = 13.405
        try await store.save(contact)
        let all = try await store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Bob Updated")
        XCTAssertEqual(all[0].lat ?? 0, 52.52, accuracy: 0.001)
    }

    func testFetchById_returnsNilForMissing() async throws {
        let store = try ContactStore(inMemory: true)
        let result = try await store.fetch(id: "00000000")
        XCTAssertNil(result)
    }

    func testFetchById_returnsContact() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "deadbeef", name: "Eve",
                                   lastSeen: nil, isOnline: true,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        let fetched = try await store.fetch(id: "deadbeef")
        XCTAssertEqual(fetched?.name, "Eve")
    }

    func testLastSeen_roundtrips() async throws {
        let store = try ContactStore(inMemory: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let contact = MeshContact(id: "aa11bb22", name: "Dave",
                                   lastSeen: date, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        let all = try await store.fetchAll()
        let delta = abs((all[0].lastSeen?.timeIntervalSince1970 ?? 0) - 1_700_000_000)
        XCTAssertLessThan(delta, 1.0)
    }

    func testDelete_removesContact() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "cafe1234", name: "Chuck",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        try await store.delete(id: "cafe1234")
        let all = try await store.fetchAll()
        XCTAssert(all.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/jarodschilke/Projekte/MeshCoreMacApp
xcodegen generate
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  -only-testing:MeshCoreMacTests/ContactStoreTests 2>&1 | tail -30
```

Expected: compile error — `ContactStore`, `MeshContact.lat` not found.

- [ ] **Step 3: Extend MeshContact**

Replace `MeshCoreMac/Models/MeshContact.swift` with:

```swift
import Foundation

struct MeshContact: Identifiable, Hashable, Sendable {
    let id: String     // Hex-Node-Adresse (z.B. "a1b2c3d4")
    var name: String
    var lastSeen: Date?
    var isOnline: Bool
    var lat: Double?
    var lon: Double?
}
```

- [ ] **Step 4: Create ContactRecord**

Create `MeshCoreMac/Services/ContactRecord.swift`:

```swift
import GRDB
import Foundation

struct ContactRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contacts"

    var id: String
    var name: String
    var lastSeen: Double?   // Date.timeIntervalSince1970
    var isOnline: Bool
    var lat: Double?
    var lon: Double?

    init(from contact: MeshContact) {
        id = contact.id
        name = contact.name
        lastSeen = contact.lastSeen?.timeIntervalSince1970
        isOnline = contact.isOnline
        lat = contact.lat
        lon = contact.lon
    }

    func toMeshContact() -> MeshContact {
        MeshContact(
            id: id,
            name: name,
            lastSeen: lastSeen.map { Date(timeIntervalSince1970: $0) },
            isOnline: isOnline,
            lat: lat,
            lon: lon
        )
    }
}
```

- [ ] **Step 5: Create ContactStore**

Create `MeshCoreMac/Services/ContactStore.swift`:

```swift
import GRDB
import Foundation

final class ContactStore: Sendable {
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
                .appendingPathComponent("contacts.sqlite")
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            dbQueue = try DatabaseQueue(path: dbURL.path)
        }
        try runMigrations()
    }

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_contacts") { db in
            try db.create(table: ContactRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lastSeen", .double)
                t.column("isOnline", .boolean).notNull()
                t.column("lat", .double)
                t.column("lon", .double)
            }
        }
        try migrator.migrate(dbQueue)
    }

    func save(_ contact: MeshContact) async throws {
        let record = ContactRecord(from: contact)
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    func fetchAll() async throws -> [MeshContact] {
        try await dbQueue.read { db in
            try ContactRecord.fetchAll(db).map { $0.toMeshContact() }
        }
    }

    func fetch(id: String) async throws -> MeshContact? {
        try await dbQueue.read { db in
            try ContactRecord.fetchOne(db, key: id)?.toMeshContact()
        }
    }

    func delete(id: String) async throws {
        try await dbQueue.write { db in
            _ = try ContactRecord.deleteOne(db, key: id)
        }
    }
}
```

- [ ] **Step 6: Run tests — expect all 6 to pass**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  -only-testing:MeshCoreMacTests/ContactStoreTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add MeshCoreMac/Models/MeshContact.swift \
        MeshCoreMac/Services/ContactRecord.swift \
        MeshCoreMac/Services/ContactStore.swift \
        MeshCoreMacTests/Services/ContactStoreTests.swift
git commit -m "feat: extend MeshContact with lat/lon, add ContactRecord + ContactStore (GRDB)"
```

---

## Task 2: Protocol Extensions — DecodedFrame + Decode Logic

This task renames two existing DecodedFrame cases, adds new ones, extends decode logic to extract lat/lon from real MeshCore wire format, and adds `encodeGetContacts()`. ChatViewModel's switch must be updated for compilation.

**MeshCore wire format used in this task:**
- **ADVERT (0x80) / SELF_INFO (0x05) payload:** `[pubkey:32][timestamp_le4][lat_f32_le4][lon_f32_le4][alt_f32_le4][name:variable_utf8_nulterminated]` — minimum 48 bytes
- **CONTACT response (0x03) payload:** `[pubkey:32][last_heard_le4][flags:1][name:variable_utf8]` — minimum 37 bytes
- **CONTACTS_START (0x02):** no payload relevant
- **END_OF_CONTACTS (0x04):** no payload relevant

**Files:**
- Modify: `MeshCoreMac/Services/MeshCoreProtocol.swift`
- Modify: `MeshCoreMac/Services/MeshCoreProtocolService.swift`
- Modify: `MeshCoreMac/ViewModels/ChatViewModel.swift`
- Modify: `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift`

- [ ] **Step 1: Add tests for new decode behavior**

Append to `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift` (inside the class body, before the closing `}`):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  -only-testing:MeshCoreMacTests/MeshCoreProtocolServiceTests 2>&1 | tail -30
```

Expected: compile error — new cases don't exist yet.

- [ ] **Step 3: Update DecodedFrame in MeshCoreProtocol.swift**

Replace the `DecodedFrame` enum section (starting at `// MARK: - Decoded Frame Typen`) with:

```swift
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
```

Also add `encodeGetContacts` to `MeshCoreProtocol.Command` — it's already there as `getContacts = 0x04`. The function goes in `MeshCoreProtocolService`.

Also add a response alias for SELF_INFO in the existing `Response` enum (after the existing `selfInfo` case):

```swift
// Already exists:  case selfInfo = 0x05
```

Check: `Response.selfInfo` already exists (`0x05`). ✓

- [ ] **Step 4: Update MeshCoreProtocolService.swift**

Replace the entire file content with:

```swift
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
```

- [ ] **Step 5: Update ChatViewModel.handleFrame switch**

In `MeshCoreMac/ViewModels/ChatViewModel.swift`, replace the `handleFrame` method's switch cases for old `deviceInfo` and `nodeStatus` with the new case names:

```swift
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
                if msg.isIncoming {
                    notificationService.sendNewMessageNotification(
                        senderName: msg.senderName,
                        preview: String(msg.text.prefix(60))
                    )
                }

            case .newDirectMessage(let msg):
                guard case .direct(let cid) = msg.kind,
                      case .direct(let ours) = conversation,
                      cid == ours else { return }
                messages.append(msg)
                try await messageStore.save(msg)
                if msg.isIncoming {
                    notificationService.sendNewMessageNotification(
                        senderName: msg.senderName,
                        preview: String(msg.text.prefix(60))
                    )
                }

            case .messageAck(let msgId):
                if let idx = messages.firstIndex(where: { $0.id.uuidString == msgId }) {
                    messages[idx].deliveryStatus = .delivered
                    try await messageStore.updateDeliveryStatus(
                        messageId: messages[idx].id, status: .delivered
                    )
                }

            case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd:
                break
            }
        } catch {
            #if DEBUG
            print("[ChatViewModel] Frame decode error: \(error)")
            #endif
        }
    }
```

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all previous tests still pass, new protocol tests pass. Total count increases.

- [ ] **Step 7: Commit**

```bash
git add MeshCoreMac/Services/MeshCoreProtocol.swift \
        MeshCoreMac/Services/MeshCoreProtocolService.swift \
        MeshCoreMac/ViewModels/ChatViewModel.swift \
        MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift
git commit -m "feat: extend DecodedFrame with position/contact cases, decode ADVERT/SELF_INFO/CONTACT frames"
```

---

## Task 3: BluetoothService — nodeEventStream + GET_CONTACTS

BluetoothService gets a second typed stream for contact/node events. ChatViewModel's existing `incomingFrames: AsyncStream<Data>` is untouched. BluetoothService decodes each incoming BLE frame twice: raw bytes go to `incomingFrames`, decoded node events go to `nodeEventStream`. GET_CONTACTS is added to the init sequence.

**Files:**
- Modify: `MeshCoreMac/Services/BluetoothServiceProtocol.swift`
- Modify: `MeshCoreMac/Services/MeshCoreBluetoothService.swift`
- Modify: `MeshCoreMacTests/Services/MockBluetoothService.swift`

- [ ] **Step 1: Update BluetoothServiceProtocol**

Replace `MeshCoreMac/Services/BluetoothServiceProtocol.swift` with:

```swift
// MeshCoreMac/Services/BluetoothServiceProtocol.swift
import CoreBluetooth
import Foundation

@MainActor
protocol BluetoothServiceProtocol: AnyObject {
    var connectionState: ConnectionState { get }
    var discoveredDevices: [CBPeripheral] { get }
    /// Rohe BLE-Frames (Node → App). ChatViewModel konsumiert diesen Stream.
    var incomingFrames: AsyncStream<Data> { get }
    /// Dekodierte Node-Ereignisse: selfInfo, nodeAdvert, contact, contactsStart/End.
    var nodeEventStream: AsyncStream<DecodedFrame> { get }

    func startScanning()
    func stopScanning()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
    func send(_ data: Data) throws
    func setLastKnownPeripheralId(_ id: UUID?)
}
```

- [ ] **Step 2: Update MockBluetoothService**

Replace `MeshCoreMacTests/Services/MockBluetoothService.swift` with:

```swift
// MeshCoreMacTests/Services/MockBluetoothService.swift
import CoreBluetooth
import Foundation
@testable import MeshCoreMac

@Observable
@MainActor
final class MockBluetoothService: BluetoothServiceProtocol {
    var connectionState: ConnectionState = .disconnected
    var discoveredDevices: [CBPeripheral] = []
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation
    let nodeEventStream: AsyncStream<DecodedFrame>
    private let nodeEventContinuation: AsyncStream<DecodedFrame>.Continuation

    var sentFrames: [Data] = []
    var scanStarted = false
    var disconnectCalled = false

    init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
        let (nodeStream, nodeCont) = AsyncStream<DecodedFrame>.makeStream()
        self.nodeEventStream = nodeStream
        self.nodeEventContinuation = nodeCont
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

    // MARK: - Test-Helpers

    func simulateIncomingFrame(_ data: Data) {
        frameContinuation.yield(data)
    }

    func simulateNodeEvent(_ frame: DecodedFrame) {
        nodeEventContinuation.yield(frame)
    }

    func simulateDisconnect() {
        connectionState = .failed(peripheralName: "Mock-Node", error: "Verbindung verloren")
    }

    func simulateConnect(peripheralName: String = "Mock-Node") {
        connectionState = .ready(peripheralName: peripheralName)
    }
}
```

- [ ] **Step 3: Update MeshCoreBluetoothService**

In `MeshCoreMac/Services/MeshCoreBluetoothService.swift`, make these changes:

**3a.** Add `nodeEventStream` and `nodeEventContinuation` properties after `frameContinuation`:

```swift
    // MARK: - Async Frame Stream
    let incomingFrames: AsyncStream<Data>
    private let frameContinuation: AsyncStream<Data>.Continuation
    let nodeEventStream: AsyncStream<DecodedFrame>
    private let nodeEventContinuation: AsyncStream<DecodedFrame>.Continuation
```

**3b.** Update `init()` to initialise both streams:

```swift
    override init() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.incomingFrames = stream
        self.frameContinuation = continuation
        let (nodeStream, nodeCont) = AsyncStream<DecodedFrame>.makeStream()
        self.nodeEventStream = nodeStream
        self.nodeEventContinuation = nodeCont
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
```

**3c.** Update `deinit` to finish both continuations:

```swift
    deinit {
        frameContinuation.finish()
        nodeEventContinuation.finish()
    }
```

**3d.** Update `didUpdateValueFor` in the `CBPeripheralDelegate` extension to route node events:

```swift
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        frameContinuation.yield(value)

        // Route decoded node events to nodeEventStream (ChatViewModel ignores these via break)
        if let decoded = try? MeshCoreProtocolService.decodeFrame(value) {
            switch decoded {
            case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd:
                nodeEventContinuation.yield(decoded)
            case .newChannelMessage, .newDirectMessage, .messageAck:
                break
            }
        }
    }
```

**3e.** Update `sendInitSequence` to also request contacts:

```swift
    private func sendInitSequence() {
        try? send(MeshCoreProtocolService.encodeAppStart())
        try? send(MeshCoreProtocolService.encodeDeviceQuery())
        try? send(MeshCoreProtocolService.encodeGetContacts())
    }
```

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass. The new `nodeEventStream` property is present but not yet consumed by any ViewModel — that's fine.

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/Services/BluetoothServiceProtocol.swift \
        MeshCoreMac/Services/MeshCoreBluetoothService.swift \
        MeshCoreMacTests/Services/MockBluetoothService.swift
git commit -m "feat: add nodeEventStream to BluetoothService, send GET_CONTACTS on connect"
```

---

## Task 4: ContactsViewModel

ContactsViewModel subscribes to `nodeEventStream`, persists contacts to ContactStore, and maintains an in-memory list for the UI. It also tracks own-node position from `selfInfo` events.

**Files:**
- Create: `MeshCoreMac/ViewModels/ContactsViewModel.swift`
- Create: `MeshCoreMacTests/ViewModels/ContactsViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MeshCoreMacTests/ViewModels/ContactsViewModelTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import MeshCoreMac

@MainActor
final class ContactsViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var contactStore: ContactStore!
    var vm: ContactsViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        contactStore = try ContactStore(inMemory: true)
        vm = ContactsViewModel(contactStore: contactStore, bluetoothService: mockBluetooth)
        await vm.start()
    }

    func testNodeAdvert_addsContactToList() async throws {
        mockBluetooth.simulateNodeEvent(
            .nodeAdvert(contactId: "a1b2c3d4", name: "Alice", lat: 48.137, lon: 11.575)
        )
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts.count, 1)
        XCTAssertEqual(vm.contacts[0].name, "Alice")
        XCTAssertTrue(vm.contacts[0].isOnline)
        XCTAssertEqual(vm.contacts[0].lat ?? 0, 48.137, accuracy: 0.001)
    }

    func testNodeAdvert_persistsToStore() async throws {
        mockBluetooth.simulateNodeEvent(
            .nodeAdvert(contactId: "a1b2c3d4", name: "Alice", lat: nil, lon: nil)
        )
        try await waitUntil { !self.vm.contacts.isEmpty }
        let stored = try await contactStore.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "Alice")
    }

    func testContactEvent_addsToList() async throws {
        let contact = MeshContact(id: "dead1234", name: "Bob",
                                   lastSeen: nil, isOnline: true,
                                   lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(contact))
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts[0].name, "Bob")
    }

    func testSelfInfo_setsOwnPosition() async throws {
        mockBluetooth.simulateNodeEvent(
            .selfInfo(nodeId: "aa11bb22", lat: 52.52, lon: 13.405, firmware: "v1.0")
        )
        try await waitUntil { self.vm.ownPosition != nil }
        XCTAssertEqual(vm.ownPosition?.latitude ?? 0, 52.52, accuracy: 0.001)
        XCTAssertEqual(vm.ownPosition?.longitude ?? 0, 13.405, accuracy: 0.001)
    }

    func testStart_loadsPersistedContacts() async throws {
        let contact = MeshContact(id: "cafe1234", name: "Charlie",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await contactStore.save(contact)

        let newVM = ContactsViewModel(contactStore: contactStore, bluetoothService: mockBluetooth)
        await newVM.start()

        XCTAssertEqual(newVM.contacts.count, 1)
        XCTAssertEqual(newVM.contacts[0].name, "Charlie")
    }

    func testUpdateContact_persistsNameChange() async throws {
        var contact = MeshContact(id: "aa11bb22", name: "Dave",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(contact))
        try await waitUntil { !self.vm.contacts.isEmpty }

        contact.name = "Dave Updated"
        await vm.updateContact(contact)

        let stored = try await contactStore.fetchAll()
        XCTAssertEqual(stored.first?.name, "Dave Updated")
        XCTAssertEqual(vm.contacts.first?.name, "Dave Updated")
    }

    // MARK: - Helper

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timeout waiting for condition")
                return
            }
            await Task.yield()
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  -only-testing:MeshCoreMacTests/ContactsViewModelTests 2>&1 | tail -20
```

Expected: compile error — `ContactsViewModel` not found.

- [ ] **Step 3: Create ContactsViewModel**

Create `MeshCoreMac/ViewModels/ContactsViewModel.swift`:

```swift
// MeshCoreMac/ViewModels/ContactsViewModel.swift
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class ContactsViewModel {
    private(set) var contacts: [MeshContact] = []
    private(set) var ownPosition: CLLocationCoordinate2D? = nil

    private let contactStore: ContactStore
    private let bluetoothService: any BluetoothServiceProtocol

    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?

    init(contactStore: ContactStore, bluetoothService: any BluetoothServiceProtocol) {
        self.contactStore = contactStore
        self.bluetoothService = bluetoothService
    }

    func start() async {
        contacts = (try? await contactStore.fetchAll()) ?? []
        startListening()
    }

    func updateContact(_ contact: MeshContact) async {
        try? await contactStore.save(contact)
        upsert(contact)
    }

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task {
            for await event in self.bluetoothService.nodeEventStream {
                guard !Task.isCancelled else { break }
                await self.handleNodeEvent(event)
            }
        }
    }

    private func handleNodeEvent(_ frame: DecodedFrame) async {
        switch frame {
        case .selfInfo(_, let lat, let lon, _):
            if let lat = lat, let lon = lon {
                ownPosition = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        case .nodeAdvert(let contactId, let name, let lat, let lon):
            var c = contacts.first(where: { $0.id == contactId })
                ?? MeshContact(id: contactId, name: name ?? contactId,
                               lastSeen: nil, isOnline: false, lat: nil, lon: nil)
            c.isOnline = true
            c.lastSeen = Date()
            if let name = name { c.name = name }
            if let lat = lat { c.lat = lat }
            if let lon = lon { c.lon = lon }
            try? await contactStore.save(c)
            upsert(c)
        case .contact(let c):
            try? await contactStore.save(c)
            upsert(c)
        case .contactsStart, .contactsEnd:
            break
        case .newChannelMessage, .newDirectMessage, .messageAck:
            break
        }
    }

    private func upsert(_ contact: MeshContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
    }

    deinit { listenerTask?.cancel() }
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' \
  -only-testing:MeshCoreMacTests/ContactsViewModelTests 2>&1 | tail -20
```

Expected: all 6 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add MeshCoreMac/ViewModels/ContactsViewModel.swift \
        MeshCoreMacTests/ViewModels/ContactsViewModelTests.swift
git commit -m "feat: add ContactsViewModel — subscribes to nodeEventStream, persists contacts"
```

---

## Task 5: AppContainer + SidebarViewModel Wiring

Wire ContactStore and ContactsViewModel into AppContainer. SidebarViewModel drops its `contacts` and `updateContact` (owned by ContactsViewModel). SidebarView gets a `contactsVM` parameter.

**Files:**
- Modify: `MeshCoreMac/App/AppContainer.swift`
- Modify: `MeshCoreMac/ViewModels/SidebarViewModel.swift`
- Modify: `MeshCoreMac/App/MeshCoreMacApp.swift` (to call `contactsViewModel.start()` on app launch)

There are no new tests for this task — the integration is covered by the existing ViewModel tests. Run the full suite to confirm nothing is broken.

- [ ] **Step 1: Update SidebarViewModel**

Replace `MeshCoreMac/ViewModels/SidebarViewModel.swift` with:

```swift
// MeshCoreMac/ViewModels/SidebarViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class SidebarViewModel {
    var channels: [MeshChannel] = []
    var selectedConversation: MeshMessage.Kind? = nil

    init() {
        loadDefaultChannels()
    }

    private func loadDefaultChannels() {
        channels = [MeshChannel(id: 0, name: "Allgemein")]
    }

    func addChannel(_ channel: MeshChannel) {
        if !channels.contains(channel) {
            channels.append(channel)
        }
    }

    func selectConversation(_ kind: MeshMessage.Kind) {
        selectedConversation = kind
    }
}
```

- [ ] **Step 2: Update AppContainer**

Replace `MeshCoreMac/App/AppContainer.swift` with:

```swift
// MeshCoreMac/App/AppContainer.swift
import Foundation

@MainActor
final class AppContainer {
    let bluetoothService: MeshCoreBluetoothService
    let messageStore: MessageStore
    let contactStore: ContactStore
    let connectionViewModel: ConnectionViewModel
    let sidebarViewModel: SidebarViewModel
    let contactsViewModel: ContactsViewModel
    let notificationService: NotificationService

    init() throws {
        bluetoothService = MeshCoreBluetoothService()
        messageStore = try MessageStore()
        contactStore = try ContactStore()
        connectionViewModel = ConnectionViewModel(bluetoothService: bluetoothService)
        sidebarViewModel = SidebarViewModel()
        notificationService = NotificationService()
        contactsViewModel = ContactsViewModel(
            contactStore: contactStore,
            bluetoothService: bluetoothService
        )
    }

    func makeChatViewModel(for conversation: MeshMessage.Kind) -> ChatViewModel {
        ChatViewModel(
            bluetoothService: bluetoothService,
            messageStore: messageStore,
            conversation: conversation,
            notificationService: notificationService
        )
    }
}
```

- [ ] **Step 3: Start ContactsViewModel on app launch**

In `MeshCoreMac/App/MeshCoreMacApp.swift`, find the `WindowGroup { MainWindowView(container: container) }` scene and add a `.task` modifier to start ContactsViewModel:

The existing file looks like:
```swift
WindowGroup {
    MainWindowView(container: container)
}
```

Change it to:
```swift
WindowGroup {
    MainWindowView(container: container)
        .task { await container.contactsViewModel.start() }
}
```

Read the full file first to find the exact location, then make this targeted edit.

- [ ] **Step 4: Run full test suite to confirm nothing broken**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass (SidebarViewModel tests don't exist for contacts since that was Phase 1 dead code, so nothing breaks).

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/ViewModels/SidebarViewModel.swift \
        MeshCoreMac/App/AppContainer.swift \
        MeshCoreMac/App/MeshCoreMacApp.swift
git commit -m "feat: wire ContactStore + ContactsViewModel into AppContainer, start on launch"
```

---

## Task 6: ContactDetailView + SidebarView Navigation

A sheet for viewing and editing a contact. The SidebarView shows the contact list from ContactsViewModel and opens the sheet on click.

**Files:**
- Create: `MeshCoreMac/Views/MainWindow/ContactDetailView.swift`
- Modify: `MeshCoreMac/Views/MainWindow/SidebarView.swift`

No new tests — UI-only components. Verify by building with `xcodebuild build`.

- [ ] **Step 1: Create ContactDetailView**

Create `MeshCoreMac/Views/MainWindow/ContactDetailView.swift`:

```swift
// MeshCoreMac/Views/MainWindow/ContactDetailView.swift
import SwiftUI

struct ContactDetailView: View {
    @State var contact: MeshContact
    let onSave: (MeshContact) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Identität") {
                LabeledContent("Node-ID", value: contact.id)
                LabeledContent("Name") {
                    TextField("Name", text: $contact.name)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Status") {
                LabeledContent("Online") {
                    HStack {
                        Circle()
                            .fill(contact.isOnline ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(contact.isOnline ? "Ja" : "Nein")
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastSeen = contact.lastSeen {
                    LabeledContent("Zuletzt gesehen",
                                   value: lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if contact.lat != nil || contact.lon != nil {
                Section("Position") {
                    if let lat = contact.lat {
                        LabeledContent("Breite", value: String(format: "%.6f°", lat))
                    }
                    if let lon = contact.lon {
                        LabeledContent("Länge", value: String(format: "%.6f°", lon))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    onSave(contact)
                    dismiss()
                }
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }
}
```

- [ ] **Step 2: Update SidebarView**

Replace `MeshCoreMac/Views/MainWindow/SidebarView.swift` with:

```swift
// MeshCoreMac/Views/MainWindow/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    let sidebarVM: SidebarViewModel
    let connectionVM: ConnectionViewModel
    let contactsVM: ContactsViewModel

    @State private var selectedContactForDetail: MeshContact? = nil

    var body: some View {
        List(selection: Binding(
            get: { sidebarVM.selectedConversation.map(ConversationID.init) },
            set: { id in
                if let kind = id?.kind { sidebarVM.selectConversation(kind) }
            }
        )) {
            Section("Kanäle") {
                ForEach(sidebarVM.channels) { channel in
                    Label("# \(channel.name)", systemImage: "number")
                        .tag(ConversationID(kind: .channel(index: channel.id)))
                }
            }

            if !contactsVM.contacts.isEmpty {
                Section("Direkt") {
                    ForEach(contactsVM.contacts) { contact in
                        HStack {
                            Label(contact.name, systemImage: "person.fill")
                                .tag(ConversationID(kind: .direct(contactId: contact.id)))
                            Spacer()
                            Circle()
                                .fill(contact.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Button {
                                selectedContactForDetail = contact
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionVM.connectionState.isConnectedOrReady ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(connectionVM.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(item: $selectedContactForDetail) { contact in
            NavigationStack {
                ContactDetailView(contact: contact) { updated in
                    Task { await contactsVM.updateContact(updated) }
                }
            }
        }
    }
}

struct ConversationID: Hashable {
    let kind: MeshMessage.Kind
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Commit**

```bash
git add MeshCoreMac/Views/MainWindow/ContactDetailView.swift \
        MeshCoreMac/Views/MainWindow/SidebarView.swift
git commit -m "feat: add ContactDetailView, SidebarView shows contacts from ContactsViewModel"
```

---

## Task 7: MapView

A SwiftUI `Map` showing all known nodes as pins. Uses `MapKit`'s modern SwiftUI API (macOS 14+). Own-node position shown in blue, contacts in green (online) or gray (offline). No MapKit entitlement needed on macOS.

**Files:**
- Create: `MeshCoreMac/Views/Map/MapView.swift`

No new tests — pure view with no logic.

- [ ] **Step 1: Create MapView**

Create `MeshCoreMac/Views/Map/MapView.swift`:

```swift
// MeshCoreMac/Views/Map/MapView.swift
import CoreLocation
import MapKit
import SwiftUI

struct NodeMapView: View {
    let contacts: [MeshContact]
    let ownPosition: CLLocationCoordinate2D?

    private var nodesWithPosition: [MeshContact] {
        contacts.filter { $0.lat != nil && $0.lon != nil }
    }

    var body: some View {
        Group {
            if ownPosition == nil && nodesWithPosition.isEmpty {
                emptyState
            } else {
                mapContent
            }
        }
        .navigationTitle("Karte")
        .frame(minWidth: 500, minHeight: 400)
    }

    private var mapContent: some View {
        Map {
            if let pos = ownPosition {
                Annotation("Mein Node", coordinate: pos) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue, in: Circle())
                }
            }
            ForEach(nodesWithPosition) { contact in
                let coord = CLLocationCoordinate2D(
                    latitude: contact.lat!,
                    longitude: contact.lon!
                )
                Annotation(contact.name, coordinate: coord) {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            contact.isOnline ? Color.green : Color.gray,
                            in: Circle()
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Keine Positionen",
            systemImage: "map",
            description: Text("Warte auf GPS-Daten von Nodes in der Nähe.")
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add MeshCoreMac/Views/Map/MapView.swift
git commit -m "feat: add NodeMapView with SwiftUI Map, shows node positions as pins"
```

---

## Task 8: UI Integration — ChatView Title + MainWindowView Map Toolbar

Resolve contact names in ChatView DM titles and add a map toolbar button to MainWindowView.

**Files:**
- Modify: `MeshCoreMac/Views/MainWindow/ChatView.swift`
- Modify: `MeshCoreMac/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Update ChatView to accept contactsVM and resolve DM title**

Read `MeshCoreMac/Views/MainWindow/ChatView.swift` (do not modify yet). The current `conversationTitle` for `.direct(let cid)` returns the raw `cid`. We need to look up the name from `contactsVM.contacts`.

Replace `MeshCoreMac/Views/MainWindow/ChatView.swift` with:

```swift
// MeshCoreMac/Views/MainWindow/ChatView.swift
import SwiftUI

struct ChatView: View {
    @Bindable var chatVM: ChatViewModel
    let conversation: MeshMessage.Kind
    let contactsVM: ContactsViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = chatVM.errorMessage {
                ErrorBannerView(message: error) {
                    chatVM.errorMessage = nil
                }
            }

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

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Nachricht eingeben…", text: $chatVM.inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)

                    let count = chatVM.inputText.utf8.count
                    Text("\(count)/\(MeshCoreProtocol.maxMessageLength)")
                        .font(.caption2)
                        .foregroundStyle(count > MeshCoreProtocol.maxMessageLength ? Color.red : Color.secondary)
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
        case .channel(let idx):
            return "Kanal \(idx)"
        case .direct(let cid):
            return contactsVM.contacts.first(where: { $0.id == cid })?.name ?? cid
        }
    }

    private func trySend() async {
        do {
            try await chatVM.send(text: chatVM.inputText)
        } catch {
            chatVM.errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Update MainWindowView**

Replace `MeshCoreMac/Views/MainWindow/MainWindowView.swift` with:

```swift
// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    @State private var dismissedError: String? = nil
    @State private var showingMap = false

    var body: some View {
        Group {
            if container.connectionViewModel.connectionState.isConnectedOrReady {
                messengerView
            } else {
                PairingView(connectionVM: container.connectionViewModel)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .overlay(alignment: .top) {
            if let err = container.connectionViewModel.errorMessage,
               err != dismissedError {
                ErrorBannerView(
                    message: err,
                    onDismiss: { dismissedError = err },
                    onRetry: { container.connectionViewModel.startScan() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: err)
            }
        }
        .onChange(of: container.connectionViewModel.errorMessage) { _, newError in
            if newError != dismissedError {
                dismissedError = nil
            }
        }
        .sheet(isPresented: $showingMap) {
            NavigationStack {
                NodeMapView(
                    contacts: container.contactsViewModel.contacts,
                    ownPosition: container.contactsViewModel.ownPosition
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { showingMap = false }
                    }
                }
            }
        }
    }

    private var messengerView: some View {
        NavigationSplitView {
            SidebarView(
                sidebarVM: container.sidebarViewModel,
                connectionVM: container.connectionViewModel,
                contactsVM: container.contactsViewModel
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let conversation = container.sidebarViewModel.selectedConversation {
                ChatView(
                    chatVM: container.makeChatViewModel(for: conversation),
                    conversation: conversation,
                    contactsVM: container.contactsViewModel
                )
            } else {
                ContentUnavailableView(
                    "Keine Konversation gewählt",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Wähle einen Kanal oder Kontakt in der Sidebar.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingMap = true
                } label: {
                    Label("Karte", systemImage: "map")
                }
                .help("Karte aller bekannten Nodes anzeigen")
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run full test suite**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/Views/MainWindow/ChatView.swift \
        MeshCoreMac/Views/MainWindow/MainWindowView.swift
git commit -m "feat: resolve DM contact names in ChatView, add Map toolbar button"
```

---

## Self-Review Checklist

### 1. Spec Coverage

| Requirement | Task |
|---|---|
| Contacts persistent in SQLite | Task 1, 4 |
| Contacts populated from BLE ADVERT | Task 2, 3, 4 |
| Contacts populated from GET_CONTACTS | Task 2, 3, 4 |
| Own node position from SELF_INFO | Task 2, 3, 4 |
| Editable contact names | Task 6 |
| Last seen + online status in detail | Task 6 |
| Map showing node positions | Task 7 |
| Map accessible from main window | Task 8 |
| DM titles show contact name | Task 8 |
| Existing tests remain green | all tasks |

### 2. Placeholder Scan

No TBD/TODO/placeholder items — all code is complete.

### 3. Type Consistency

- `MeshContact(id:name:lastSeen:isOnline:lat:lon:)` — defined Task 1, used consistently Tasks 2–8
- `ContactsViewModel.contacts: [MeshContact]` — defined Task 4, read in Tasks 6, 7, 8
- `BluetoothServiceProtocol.nodeEventStream: AsyncStream<DecodedFrame>` — defined Task 3, consumed Task 4
- `NodeMapView` (not `MapView`) — defined Task 7, used Task 8 (avoids collision with SwiftUI `MapView` type alias)
- `DecodedFrame.selfInfo(nodeId:lat:lon:firmware:)` — defined Task 2, handled Tasks 3, 4, ViewModel switch
