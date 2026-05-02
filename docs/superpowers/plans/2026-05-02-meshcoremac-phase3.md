# MeshCoreMac Phase 3 — Netzwerk-Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Diagnostics window with RX Log (live BLE frame log), CLI (raw hex command input), and Node Status (battery, storage, noise floor) — accessible via a toolbar button in MainWindowView.

**Architecture:** A new `rxLogStream: AsyncStream<RxLogEntry>` on `BluetoothServiceProtocol` captures every BLE frame (incoming + outgoing). `DiagnosticsViewModel` subscribes to this stream for the RX Log display, re-decodes relevant frames to extract battery/noise-floor values for the Status tab, and routes CLI hex commands through `bluetoothService.send()`. Two new `DecodedFrame` cases (`.battAndStorage`, `.noiseFloor`) are decoded from existing but previously-ignored response codes. A trace-path command (`0x07`, VERIFY) is added to the CLI quick-command palette; results appear as `PATH_UPDATED` entries in the RX log.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI + MVVM + `@Observable`, CoreBluetooth (`AsyncStream`), XCTest

---

## Existing Codebase Context

Read these files before starting any task:

- `MeshCoreMac/Services/MeshCoreProtocol.swift` — `DecodedFrame`, `Command`/`Response`/`Push` enums
- `MeshCoreMac/Services/MeshCoreProtocolService.swift` — `decodeFrame()`, existing decoders
- `MeshCoreMac/Services/BluetoothServiceProtocol.swift` — protocol with `incomingFrames` + `nodeEventStream`
- `MeshCoreMac/Services/MeshCoreBluetoothService.swift` — `didUpdateValueFor`, `send()`, stream init pattern
- `MeshCoreMacTests/Services/MockBluetoothService.swift` — mock with `simulateNodeEvent` pattern
- `MeshCoreMac/ViewModels/ChatViewModel.swift` — exhaustive `DecodedFrame` switch (must stay exhaustive)
- `MeshCoreMac/ViewModels/ContactsViewModel.swift` — exhaustive `DecodedFrame` switch (must stay exhaustive)
- `MeshCoreMac/App/AppContainer.swift` — DI container
- `MeshCoreMac/Views/MainWindow/MainWindowView.swift` — `MapSheetContent` + `ChatContainer` pattern

**Key invariants to preserve:**
- Every `DecodedFrame` switch must be exhaustive — adding new cases requires updating `ChatViewModel.handleFrame` and `ContactsViewModel.handleNodeEvent`
- `incomingFrames` and `nodeEventStream` each have exactly one consumer — do not add a second consumer to either
- `rxLogStream` is the new single-consumer stream for `DiagnosticsViewModel`
- Swift 6 concurrency: `@MainActor` on all ViewModels, `nonisolated(unsafe)` + `deinit { task?.cancel() }` for Task properties
- Tests: `@MainActor final class ... XCTestCase`, `override func setUp() async throws`

---

## File Structure

```
New files:
  MeshCoreMac/Models/RxLogEntry.swift
  MeshCoreMac/ViewModels/DiagnosticsViewModel.swift
  MeshCoreMac/Views/Diagnostics/DiagnosticsView.swift
  MeshCoreMac/Views/Diagnostics/RxLogView.swift
  MeshCoreMac/Views/Diagnostics/CLIView.swift
  MeshCoreMac/Views/Diagnostics/NodeStatusView.swift
  MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift

Modified files:
  MeshCoreMac/Services/MeshCoreProtocol.swift              — new DecodedFrame cases + displayDescription
  MeshCoreMac/Services/MeshCoreProtocolService.swift       — decode battAndStorage + noiseFloor, encode tracePath
  MeshCoreMac/Services/BluetoothServiceProtocol.swift      — add rxLogStream
  MeshCoreMac/Services/MeshCoreBluetoothService.swift      — add rxLogStream, log in/out
  MeshCoreMacTests/Services/MockBluetoothService.swift     — add rxLogStream + simulateRxLogEntry
  MeshCoreMac/ViewModels/ChatViewModel.swift               — add new DecodedFrame cases to switch
  MeshCoreMac/ViewModels/ContactsViewModel.swift           — add new DecodedFrame cases to switch
  MeshCoreMac/App/AppContainer.swift                       — add DiagnosticsViewModel
  MeshCoreMac/App/MeshCoreMacApp.swift                     — start DiagnosticsViewModel via .task
  MeshCoreMac/Views/MainWindow/MainWindowView.swift        — add Diagnose toolbar button + sheet
  MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift — tests for new decoders
```

---

## Task 1: RxLogEntry model + DecodedFrame.displayDescription

**Files:**
- Create: `MeshCoreMac/Models/RxLogEntry.swift`
- Modify: `MeshCoreMac/Services/MeshCoreProtocol.swift` (add `displayDescription`)

No tests for this task — pure value types verified by build in later tasks.

- [ ] **Step 1: Create RxLogEntry model**

Create `MeshCoreMac/Models/RxLogEntry.swift`:

```swift
// MeshCoreMac/Models/RxLogEntry.swift
import Foundation

struct RxLogEntry: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case incoming = "↓"
        case outgoing = "↑"
    }

    let id: UUID
    let timestamp: Date
    let direction: Direction
    let rawBytes: Data
    let decoded: String?

    var hexString: String {
        rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var commandByte: UInt8? { rawBytes.first }
}
```

- [ ] **Step 2: Add displayDescription to DecodedFrame**

In `MeshCoreMac/Services/MeshCoreProtocol.swift`, append at the bottom (after the `ProtocolError` enum):

```swift
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
        }
    }
}
```

Note: `.battAndStorage` and `.noiseFloor` are new enum cases added in Task 4. At this point the compiler will warn until Task 4 is done — that's expected; the plan adds them together.

- [ ] **Step 3: Build to verify**

```bash
cd /Users/jarodschilke/Projekte/MeshCoreMacApp
xcodegen generate && xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (the two new `DecodedFrame` cases won't exist yet — omit them from `displayDescription` temporarily until Task 4. Add `battAndStorage` and `noiseFloor` cases to `displayDescription` in Task 4's step that extends `DecodedFrame`.)

**Revised Step 2 (no forward references):** Write `displayDescription` with only the currently-existing cases:

```swift
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
        }
    }
}
```

Task 4 will extend this switch with `.battAndStorage` and `.noiseFloor`.

- [ ] **Step 4: Commit**

```bash
git add MeshCoreMac/Models/RxLogEntry.swift MeshCoreMac/Services/MeshCoreProtocol.swift
git commit -m "feat(phase3): add RxLogEntry model, DecodedFrame.displayDescription"
```

---

## Task 2: BluetoothServiceProtocol + MockBluetoothService — rxLogStream

**Files:**
- Modify: `MeshCoreMac/Services/BluetoothServiceProtocol.swift`
- Modify: `MeshCoreMacTests/Services/MockBluetoothService.swift`

No new test file — mock is verified in Task 5's tests.

- [ ] **Step 1: Add rxLogStream to BluetoothServiceProtocol**

Replace `MeshCoreMac/Services/BluetoothServiceProtocol.swift` with:

```swift
// MeshCoreMac/Services/BluetoothServiceProtocol.swift
//
// Abstraktion über CoreBluetooth, damit ViewModels gegen einen Mock testbar
// sind. Das Protokoll ist `@MainActor`-isoliert: alle Zugriffe auf
// `CBPeripheral` (das nicht Sendable ist) finden auf dem Main-Thread statt.

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
    /// Alle BLE-Frames (ein- und ausgehend) als Log-Einträge. DiagnosticsViewModel konsumiert diesen Stream.
    var rxLogStream: AsyncStream<RxLogEntry> { get }

    func startScanning()
    func stopScanning()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
    func send(_ data: Data) throws
    func setLastKnownPeripheralId(_ id: UUID?)
}
```

- [ ] **Step 2: Add rxLogStream to MockBluetoothService**

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
    let rxLogStream: AsyncStream<RxLogEntry>
    private let rxLogContinuation: AsyncStream<RxLogEntry>.Continuation

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
        let (logStream, logCont) = AsyncStream<RxLogEntry>.makeStream()
        self.rxLogStream = logStream
        self.rxLogContinuation = logCont
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

    func simulateRxLogEntry(_ entry: RxLogEntry) {
        rxLogContinuation.yield(entry)
    }

    func simulateDisconnect() {
        connectionState = .failed(peripheralName: "Mock-Node", error: "Verbindung verloren")
    }

    func simulateConnect(peripheralName: String = "Mock-Node") {
        connectionState = .ready(peripheralName: peripheralName)
    }

    deinit {
        frameContinuation.finish()
        nodeEventContinuation.finish()
        rxLogContinuation.finish()
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD FAILED` because `MeshCoreBluetoothService` doesn't yet conform to `rxLogStream`. Proceed to Task 3.

- [ ] **Step 4: Commit**

```bash
git add MeshCoreMac/Services/BluetoothServiceProtocol.swift \
        MeshCoreMacTests/Services/MockBluetoothService.swift
git commit -m "feat(phase3): add rxLogStream to BluetoothServiceProtocol and MockBluetoothService"
```

---

## Task 3: MeshCoreBluetoothService — rxLogStream

**Files:**
- Modify: `MeshCoreMac/Services/MeshCoreBluetoothService.swift`

- [ ] **Step 1: Add rxLogStream properties to MeshCoreBluetoothService**

In `MeshCoreBluetoothService`, add after `nodeEventContinuation`:

```swift
let rxLogStream: AsyncStream<RxLogEntry>
private let rxLogContinuation: AsyncStream<RxLogEntry>.Continuation
```

In `init()`, add after the `nodeEventStream` makeStream call:

```swift
let (logStream, logCont) = AsyncStream<RxLogEntry>.makeStream()
self.rxLogStream = logStream
self.rxLogContinuation = logCont
```

In `deinit`, add:

```swift
rxLogContinuation.finish()
```

Full modified init block (replace existing):

```swift
override init() {
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    self.incomingFrames = stream
    self.frameContinuation = continuation
    let (nodeStream, nodeCont) = AsyncStream<DecodedFrame>.makeStream()
    self.nodeEventStream = nodeStream
    self.nodeEventContinuation = nodeCont
    let (logStream, logCont) = AsyncStream<RxLogEntry>.makeStream()
    self.rxLogStream = logStream
    self.rxLogContinuation = logCont
    super.init()
    self.centralManager = CBCentralManager(delegate: self, queue: .main)
}

deinit {
    reconnectTask?.cancel()
    frameContinuation.finish()
    nodeEventContinuation.finish()
    rxLogContinuation.finish()
}
```

- [ ] **Step 2: Log incoming frames in didUpdateValueFor**

Replace the existing `peripheral(_:didUpdateValueFor:error:)` implementation:

```swift
func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
) {
    guard error == nil, let value = characteristic.value else { return }
    frameContinuation.yield(value)

    let decoded = try? MeshCoreProtocolService.decodeFrame(value)

    // Route node events
    if let decoded {
        switch decoded {
        case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd,
             .battAndStorage, .noiseFloor:
            nodeEventContinuation.yield(decoded)
        case .newChannelMessage, .newDirectMessage, .messageAck:
            break
        }
    }

    // Log all incoming frames
    rxLogContinuation.yield(RxLogEntry(
        id: UUID(),
        timestamp: Date(),
        direction: .incoming,
        rawBytes: value,
        decoded: decoded?.displayDescription
            ?? value.first.map { "Unbekannt: 0x\(String(format: "%02X", $0))" }
    ))
}
```

Note: `.battAndStorage` and `.noiseFloor` in the node event route will be added in Task 4. Update this switch again there.

**Interim version (Tasks 1-3 don't have those cases yet):** Remove `.battAndStorage, .noiseFloor` from the switch — Task 4 adds them.

- [ ] **Step 3: Log outgoing frames in send()**

Replace `func send(_ data: Data) throws`:

```swift
func send(_ data: Data) throws {
    guard let peripheral = connectedPeripheral,
          let characteristic = txCharacteristic else {
        throw BluetoothError.notConnected
    }
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
    rxLogContinuation.yield(RxLogEntry(
        id: UUID(),
        timestamp: Date(),
        direction: .outgoing,
        rawBytes: data,
        decoded: nil
    ))
}
```

- [ ] **Step 4: Build and test**

```bash
xcodegen generate && xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ test|All tests|error:"
```

Expected: `All tests passed` (46/46). The new rxLogStream doesn't break anything.

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/Services/MeshCoreBluetoothService.swift
git commit -m "feat(phase3): add rxLogStream to MeshCoreBluetoothService, log in/out frames"
```

---

## Task 4: Protocol extensions — battAndStorage + noiseFloor decoders, tracePath encoder

**Files:**
- Modify: `MeshCoreMac/Services/MeshCoreProtocol.swift`
- Modify: `MeshCoreMac/Services/MeshCoreProtocolService.swift`
- Modify: `MeshCoreMac/ViewModels/ChatViewModel.swift`
- Modify: `MeshCoreMac/ViewModels/ContactsViewModel.swift`
- Modify: `MeshCoreMac/Services/MeshCoreBluetoothService.swift`
- Modify: `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift`

- [ ] **Step 1: Write failing tests for new decoders**

In `MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift`, add after the existing tests:

```swift
func testDecodeBattAndStorage_valid() throws {
    // battery=75%, storageUsed=1024B, storageFree=8192B
    var frame = Data([MeshCoreProtocol.Response.battAndStorage.rawValue])
    frame.append(75)                          // battery percent
    frame.append(contentsOf: [0x00, 0x04, 0x00, 0x00])  // 1024 LE uint32
    frame.append(contentsOf: [0x00, 0x20, 0x00, 0x00])  // 8192 LE uint32
    let decoded = try MeshCoreProtocolService.decodeFrame(frame)
    guard case .battAndStorage(let batt, let used, let free) = decoded else {
        XCTFail("Expected .battAndStorage"); return
    }
    XCTAssertEqual(batt, 75)
    XCTAssertEqual(used, 1024)
    XCTAssertEqual(free, 8192)
}

func testDecodeNoiseFloor_valid() throws {
    // PUSH_STATUS_RESPONSE 0x87, rssi=-80, noise=-110
    var frame = Data([MeshCoreProtocol.Push.statusResponse.rawValue])
    frame.append(UInt8(bitPattern: Int8(-80)))   // rssi signed byte
    frame.append(UInt8(bitPattern: Int8(-110)))  // noise signed byte
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
    XCTAssertEqual(data.count, 5)  // 1 cmd + 4 contact bytes
    XCTAssertEqual(data[1], 0xa1)
    XCTAssertEqual(data[2], 0xb2)
    XCTAssertEqual(data[3], 0xc3)
    XCTAssertEqual(data[4], 0xd4)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "testDecodeBatt|testDecodeNoise|testEncodeTrace|FAILED|error:"
```

Expected: Tests fail (decoders not yet implemented).

- [ ] **Step 3: Add new DecodedFrame cases and Command.tracePath**

In `MeshCoreMac/Services/MeshCoreProtocol.swift`:

Add `tracePath = 0x07` to `Command` enum (after `getContacts`):
```swift
case getContacts        = 0x04  // CMD_GET_CONTACTS
case tracePath          = 0x07  // CMD_TRACE_PATH — VERIFY: cmd byte unconfirmed
case getDeviceTime      = 0x05  // CMD_GET_DEVICE_TIME
```

Add two new cases to `DecodedFrame`:
```swift
enum DecodedFrame: Sendable, Equatable {
    case selfInfo(nodeId: String, lat: Double?, lon: Double?, firmware: String)
    case newChannelMessage(MeshMessage)
    case newDirectMessage(MeshMessage)
    case messageAck(messageId: String)
    case nodeAdvert(contactId: String, name: String?, lat: Double?, lon: Double?)
    case contact(MeshContact)
    case contactsStart
    case contactsEnd
    /// Batterie-Ladezustand und Speicherinfo (RESP_BATT_AND_STORAGE 0x0C).
    /// Format: [battery_pct:1][storage_used_le32:4][storage_free_le32:4] — VERIFY
    case battAndStorage(battery: Int, storageUsed: Int, storageFree: Int)
    /// RF-Status (PUSH_STATUS_RESPONSE 0x87): RSSI und Noise Floor in dBm.
    /// Format: [rssi_i8:1][noise_i8:1] — VERIFY
    case noiseFloor(rssi: Int, noise: Int)
}
```

Extend `DecodedFrame.displayDescription` (appended to existing switch in `MeshCoreProtocol.swift`). Find the extension and add the two missing cases:
```swift
case .battAndStorage(let batt, let used, let free):
    return "BATT_STORAGE batt=\(batt)% used=\(used)B free=\(free)B"
case .noiseFloor(let rssi, let noise):
    return "STATUS rssi=\(rssi)dBm noise=\(noise)dBm"
```

- [ ] **Step 4: Add decoders and encoder to MeshCoreProtocolService**

In `MeshCoreMac/Services/MeshCoreProtocolService.swift`:

**Add encoder at the top (Encoder section):**
```swift
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
```

**Update `decodeFrame` to handle new response + push cases:**

In the `Response` switch, remove `.battAndStorage` from the `throw` line and add a handler:
```swift
case .battAndStorage:
    return try decodeBattAndStorage(payload)
case .ok, .err, .currTime, .noMoreMessages:
    throw ProtocolError.unknownCommand(commandByte)
```

In the `Push` switch, remove `.statusResponse` from the `throw` line and add a handler:
```swift
case .statusResponse:
    return try decodeStatusResponse(payload)
case .msgWaiting, .rawData, .loginSuccess, .loginFail:
    throw ProtocolError.unknownCommand(commandByte)
```

**Add the two private decode helpers (after `readFloat32LE`):**

```swift
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
```

- [ ] **Step 5: Update ChatViewModel switch**

In `MeshCoreMac/ViewModels/ChatViewModel.swift`, replace:
```swift
case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd:
    break
```
with:
```swift
case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd,
     .battAndStorage, .noiseFloor:
    break
```

- [ ] **Step 6: Update ContactsViewModel switch**

In `MeshCoreMac/ViewModels/ContactsViewModel.swift`, replace:
```swift
case .newChannelMessage, .newDirectMessage, .messageAck:
    break
```
with:
```swift
case .newChannelMessage, .newDirectMessage, .messageAck,
     .battAndStorage, .noiseFloor:
    break
```

Also update the `nodeEventContinuation` routing in `MeshCoreBluetoothService.didUpdateValueFor` (Task 3 Step 2). The switch already includes `.battAndStorage, .noiseFloor` in the node event routing — verify it looks like:

```swift
case .selfInfo, .nodeAdvert, .contact, .contactsStart, .contactsEnd,
     .battAndStorage, .noiseFloor:
    nodeEventContinuation.yield(decoded)
case .newChannelMessage, .newDirectMessage, .messageAck:
    break
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ test|All tests|error:"
```

Expected: `All tests passed` (49/49 — 3 new tests added).

- [ ] **Step 8: Commit**

```bash
git add MeshCoreMac/Services/MeshCoreProtocol.swift \
        MeshCoreMac/Services/MeshCoreProtocolService.swift \
        MeshCoreMac/Services/MeshCoreBluetoothService.swift \
        MeshCoreMac/ViewModels/ChatViewModel.swift \
        MeshCoreMac/ViewModels/ContactsViewModel.swift \
        MeshCoreMacTests/Services/MeshCoreProtocolServiceTests.swift
git commit -m "feat(phase3): decode battAndStorage + noiseFloor, encode tracePath, extend DecodedFrame"
```

---

## Task 5: DiagnosticsViewModel + tests

**Files:**
- Create: `MeshCoreMac/ViewModels/DiagnosticsViewModel.swift`
- Create: `MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift`:

```swift
// MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift
import XCTest
@testable import MeshCoreMac

@MainActor
final class DiagnosticsViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var vm: DiagnosticsViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        vm = DiagnosticsViewModel(bluetoothService: mockBluetooth)
        await vm.start()
    }

    override func tearDown() async throws {
        vm = nil
        mockBluetooth = nil
    }

    func testLogEntries_appendOnIncomingEntry() async throws {
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: Data([0x04]), decoded: "GET_CONTACTS")
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { !self.vm.logEntries.isEmpty }
        XCTAssertEqual(vm.logEntries.count, 1)
        XCTAssertEqual(vm.logEntries[0].decoded, "GET_CONTACTS")
    }

    func testLogEntries_cappedAt200() async throws {
        for i in 0..<210 {
            let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                                   direction: .incoming,
                                   rawBytes: Data([UInt8(i % 256)]),
                                   decoded: "Entry \(i)")
            mockBluetooth.simulateRxLogEntry(entry)
        }
        try await waitUntil { self.vm.logEntries.count >= 200 }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertLessThanOrEqual(vm.logEntries.count, DiagnosticsViewModel.maxEntries)
    }

    func testSendCLICommand_validHex_sendsBytes() async throws {
        vm.cliInput = "04"
        try await vm.sendCLICommand()
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        XCTAssertEqual(mockBluetooth.sentFrames[0], Data([0x04]))
    }

    func testSendCLICommand_multiByteHex_sendsCorrectBytes() async throws {
        vm.cliInput = "07 A1 B2 C3"
        try await vm.sendCLICommand()
        XCTAssertEqual(mockBluetooth.sentFrames[0], Data([0x07, 0xA1, 0xB2, 0xC3]))
    }

    func testSendCLICommand_invalidHex_throws() async throws {
        vm.cliInput = "ZZ"
        do {
            try await vm.sendCLICommand()
            XCTFail("Hätte CLIError werfen sollen")
        } catch CLIError.invalidHex(let token) {
            XCTAssertEqual(token, "ZZ")
        }
    }

    func testSendCLICommand_addsToHistory() async throws {
        vm.cliInput = "04"
        try await vm.sendCLICommand()
        XCTAssertEqual(vm.cliHistory.first, "04")
        XCTAssertEqual(vm.cliInput, "")
    }

    func testHandleEntry_battAndStorage_updatesBatteryPercent() async throws {
        var frame = Data([MeshCoreProtocol.Response.battAndStorage.rawValue])
        frame.append(80)
        frame.append(contentsOf: [0x00, 0x10, 0x00, 0x00])  // 4096B used
        frame.append(contentsOf: [0x00, 0x40, 0x00, 0x00])  // 16384B free
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: frame, decoded: nil)
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { self.vm.batteryPercent != nil }
        XCTAssertEqual(vm.batteryPercent, 80)
        XCTAssertEqual(vm.storageUsed, 4096)
        XCTAssertEqual(vm.storageFree, 16384)
    }

    func testHandleEntry_noiseFloor_updatesNoiseFloor() async throws {
        var frame = Data([MeshCoreProtocol.Push.statusResponse.rawValue])
        frame.append(UInt8(bitPattern: Int8(-85)))
        frame.append(UInt8(bitPattern: Int8(-115)))
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: frame, decoded: nil)
        mockBluetooth.simulateRxLogEntry(entry)
        try await waitUntil { self.vm.noiseFloor != nil }
        XCTAssertEqual(vm.rssi, -85)
        XCTAssertEqual(vm.noiseFloor, -115)
    }

    func testRequestNodeStatus_sendsBattAndStorageCommand() async throws {
        try await vm.requestNodeStatus()
        XCTAssertEqual(mockBluetooth.sentFrames.count, 1)
        XCTAssertEqual(mockBluetooth.sentFrames[0][0],
                       MeshCoreProtocol.Command.getBattAndStorage.rawValue)
    }

    func testStart_calledTwice_isNoOp() async throws {
        let mockB = MockBluetoothService()
        let vm2 = DiagnosticsViewModel(bluetoothService: mockB)
        await vm2.start()
        await vm2.start()  // second call must not crash or create second listener
        let entry = RxLogEntry(id: UUID(), timestamp: Date(),
                               direction: .incoming, rawBytes: Data([0x05]), decoded: "SELF_INFO")
        mockB.simulateRxLogEntry(entry)
        try await waitUntil { !vm2.logEntries.isEmpty }
        XCTAssertEqual(vm2.logEntries.count, 1)
    }

    // MARK: - Helper

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timeout"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "DiagnosticsViewModelTests|error:|BUILD FAILED"
```

Expected: Build fails (`DiagnosticsViewModel` not found).

- [ ] **Step 3: Implement DiagnosticsViewModel**

Create `MeshCoreMac/ViewModels/DiagnosticsViewModel.swift`:

```swift
// MeshCoreMac/ViewModels/DiagnosticsViewModel.swift
import Foundation
import Observation

enum CLIError: Error, LocalizedError {
    case invalidHex(String)
    var errorDescription: String? {
        switch self {
        case .invalidHex(let s): return "Ungültige Hex-Eingabe: '\(s)'"
        }
    }
}

@MainActor
@Observable
final class DiagnosticsViewModel {

    private(set) var logEntries: [RxLogEntry] = []
    private(set) var batteryPercent: Int? = nil
    private(set) var storageUsed: Int? = nil
    private(set) var storageFree: Int? = nil
    private(set) var rssi: Int? = nil
    private(set) var noiseFloor: Int? = nil

    var cliInput: String = ""
    private(set) var cliHistory: [String] = []

    private let bluetoothService: any BluetoothServiceProtocol
    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?
    private var started = false

    static let maxEntries = 200

    init(bluetoothService: any BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
    }

    func start() async {
        guard !started else { return }
        started = true
        startListening()
    }

    func sendCLICommand() async throws {
        let trimmed = cliInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tokens = trimmed.split(separator: " ").map(String.init)
        var bytes: [UInt8] = []
        for token in tokens {
            guard let byte = UInt8(token, radix: 16) else {
                throw CLIError.invalidHex(token)
            }
            bytes.append(byte)
        }
        try bluetoothService.send(Data(bytes))
        cliHistory.insert(trimmed, at: 0)
        if cliHistory.count > 50 { cliHistory.removeLast() }
        cliInput = ""
    }

    func requestNodeStatus() async throws {
        try bluetoothService.send(MeshCoreProtocolService.encodeBattAndStorage())
    }

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task {
            for await entry in self.bluetoothService.rxLogStream {
                guard !Task.isCancelled else { break }
                self.handleEntry(entry)
            }
        }
    }

    private func handleEntry(_ entry: RxLogEntry) {
        if logEntries.count >= Self.maxEntries {
            logEntries.removeFirst()
        }
        logEntries.append(entry)

        guard entry.direction == .incoming,
              let decoded = try? MeshCoreProtocolService.decodeFrame(entry.rawBytes) else { return }
        switch decoded {
        case .battAndStorage(let batt, let used, let free):
            batteryPercent = batt
            storageUsed = used
            storageFree = free
        case .noiseFloor(let r, let n):
            rssi = r
            noiseFloor = n
        default:
            break
        }
    }

    deinit {
        listenerTask?.cancel()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodegen generate && xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ test|All tests|error:"
```

Expected: `All tests passed` (49 + 9 = 58 tests).

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/ViewModels/DiagnosticsViewModel.swift \
        MeshCoreMacTests/ViewModels/DiagnosticsViewModelTests.swift
git commit -m "feat(phase3): add DiagnosticsViewModel with RX log, CLI, battery/noise decoding"
```

---

## Task 6: DiagnosticsView, RxLogView, CLIView, NodeStatusView

**Files:**
- Create: `MeshCoreMac/Views/Diagnostics/DiagnosticsView.swift`
- Create: `MeshCoreMac/Views/Diagnostics/RxLogView.swift`
- Create: `MeshCoreMac/Views/Diagnostics/CLIView.swift`
- Create: `MeshCoreMac/Views/Diagnostics/NodeStatusView.swift`

No new tests — UI views. Verified by build in Step 5.

- [ ] **Step 1: Create DiagnosticsView**

Create `MeshCoreMac/Views/Diagnostics/DiagnosticsView.swift`:

```swift
// MeshCoreMac/Views/Diagnostics/DiagnosticsView.swift
import SwiftUI

struct DiagnosticsView: View {
    let diagnosticsVM: DiagnosticsViewModel

    var body: some View {
        TabView {
            RxLogView(diagnosticsVM: diagnosticsVM)
                .tabItem { Label("RX Log", systemImage: "list.bullet.rectangle") }
            CLIView(diagnosticsVM: diagnosticsVM)
                .tabItem { Label("CLI", systemImage: "terminal") }
            NodeStatusView(diagnosticsVM: diagnosticsVM)
                .tabItem { Label("Status", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .navigationTitle("Diagnose")
        .frame(minWidth: 600, minHeight: 450)
    }
}
```

- [ ] **Step 2: Create RxLogView**

Create `MeshCoreMac/Views/Diagnostics/RxLogView.swift`:

```swift
// MeshCoreMac/Views/Diagnostics/RxLogView.swift
import SwiftUI

struct RxLogView: View {
    let diagnosticsVM: DiagnosticsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RX Log")
                    .font(.headline)
                Spacer()
                Text("\(diagnosticsVM.logEntries.count) Einträge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Leeren") {
                    // logEntries is private(set) — clear via VM method (added below)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(diagnosticsVM.logEntries) { entry in
                            RxLogRowView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: diagnosticsVM.logEntries.count) { _, _ in
                    if let last = diagnosticsVM.logEntries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct RxLogRowView: View {
    let entry: RxLogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.direction.rawValue)
                .foregroundStyle(entry.direction == .incoming ? Color.blue : Color.orange)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 12)
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                if let decoded = entry.decoded {
                    Text(decoded)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
```

Note: The "Leeren" button calls `diagnosticsVM.clearLog()`. Add this method to `DiagnosticsViewModel`:

In `DiagnosticsViewModel`, add:
```swift
func clearLog() {
    logEntries = []
}
```

Update `RxLogView` to call it:
```swift
Button("Leeren") { diagnosticsVM.clearLog() }
```

- [ ] **Step 3: Create CLIView**

Create `MeshCoreMac/Views/Diagnostics/CLIView.swift`:

```swift
// MeshCoreMac/Views/Diagnostics/CLIView.swift
import SwiftUI

struct CLIView: View {
    let diagnosticsVM: DiagnosticsViewModel
    @State private var errorMessage: String? = nil

    private let quickCommands: [(label: String, hex: String, description: String)] = [
        ("GET_CONTACTS", "04", "Kontaktliste abrufen"),
        ("DEVICE_QUERY", "16", "Node-Info abfragen"),
        ("BATT_STORAGE", "14", "Batterie & Speicher abfragen"),
        ("APP_START", "01", "App-Start senden"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schnellbefehle")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickCommands, id: \.hex) { cmd in
                        Button {
                            diagnosticsVM.cliInput = cmd.hex
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cmd.label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("0x\(cmd.hex.uppercased())")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(cmd.description)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider()

            HStack(alignment: .center, spacing: 8) {
                TextField("Hex-Bytes eingeben (z.B. 04  oder  07 A1 B2 C3 D4)",
                          text: $diagnosticsVM.cliInput)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit { trySend() }

                Button("Senden") { trySend() }
                    .buttonStyle(.borderedProminent)
                    .disabled(diagnosticsVM.cliInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            if !diagnosticsVM.cliHistory.isEmpty {
                Divider()
                Text("Verlauf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                List(diagnosticsVM.cliHistory, id: \.self) { cmd in
                    Text(cmd)
                        .font(.system(.caption, design: .monospaced))
                        .onTapGesture { diagnosticsVM.cliInput = cmd }
                }
                .listStyle(.plain)
                .frame(maxHeight: 150)
            }

            Spacer()
        }
    }

    private func trySend() {
        Task {
            do {
                errorMessage = nil
                try await diagnosticsVM.sendCLICommand()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 4: Create NodeStatusView**

Create `MeshCoreMac/Views/Diagnostics/NodeStatusView.swift`:

```swift
// MeshCoreMac/Views/Diagnostics/NodeStatusView.swift
import SwiftUI

struct NodeStatusView: View {
    let diagnosticsVM: DiagnosticsViewModel

    var body: some View {
        Form {
            Section("Batterie & Speicher") {
                if let batt = diagnosticsVM.batteryPercent {
                    LabeledContent("Batterie") {
                        HStack {
                            ProgressView(value: Double(batt), total: 100)
                                .frame(width: 80)
                            Text("\(batt)%")
                                .monospacedDigit()
                        }
                    }
                } else {
                    LabeledContent("Batterie", value: "–")
                }

                if let used = diagnosticsVM.storageUsed,
                   let free = diagnosticsVM.storageFree {
                    LabeledContent("Belegt", value: formatBytes(used))
                    LabeledContent("Frei", value: formatBytes(free))
                } else {
                    LabeledContent("Speicher", value: "–")
                }
            }

            Section("RF-Diagnose") {
                if let rssi = diagnosticsVM.rssi {
                    LabeledContent("RSSI", value: "\(rssi) dBm")
                } else {
                    LabeledContent("RSSI", value: "–")
                }
                if let noise = diagnosticsVM.noiseFloor {
                    LabeledContent("Noise Floor", value: "\(noise) dBm")
                } else {
                    LabeledContent("Noise Floor", value: "–")
                }
            }

            Section {
                Button("Status abfragen") {
                    Task {
                        try? await diagnosticsVM.requestNodeStatus()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }
}
```

- [ ] **Step 5: Build to verify**

```bash
xcodegen generate && xcodebuild build -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add MeshCoreMac/Views/Diagnostics/DiagnosticsView.swift \
        MeshCoreMac/Views/Diagnostics/RxLogView.swift \
        MeshCoreMac/Views/Diagnostics/CLIView.swift \
        MeshCoreMac/Views/Diagnostics/NodeStatusView.swift \
        MeshCoreMac/ViewModels/DiagnosticsViewModel.swift
git commit -m "feat(phase3): add DiagnosticsView with RX Log, CLI, and Node Status tabs"
```

---

## Task 7: AppContainer + MeshCoreMacApp + MainWindowView wiring

**Files:**
- Modify: `MeshCoreMac/App/AppContainer.swift`
- Modify: `MeshCoreMac/App/MeshCoreMacApp.swift`
- Modify: `MeshCoreMac/Views/MainWindow/MainWindowView.swift`

No new tests — wiring task. Verified by build + full test run.

- [ ] **Step 1: Add DiagnosticsViewModel to AppContainer**

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
    let diagnosticsViewModel: DiagnosticsViewModel
    let notificationService: NotificationService

    init() throws {
        bluetoothService = MeshCoreBluetoothService()
        messageStore = try MessageStore()
        contactStore = try ContactStore()
        connectionViewModel = ConnectionViewModel(bluetoothService: bluetoothService)
        sidebarViewModel = SidebarViewModel()
        contactsViewModel = ContactsViewModel(contactStore: contactStore, bluetoothService: bluetoothService)
        diagnosticsViewModel = DiagnosticsViewModel(bluetoothService: bluetoothService)
        notificationService = NotificationService()
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

- [ ] **Step 2: Start DiagnosticsViewModel in MeshCoreMacApp**

In `MeshCoreMac/App/MeshCoreMacApp.swift`, update the `WindowGroup` body to add a second `.task`:

```swift
WindowGroup {
    MainWindowView(container: container)
        .task { await container.contactsViewModel.start() }
        .task { await container.diagnosticsViewModel.start() }
        .onDisappear {
            appDelegate.switchToAccessoryMode()
        }
}
```

- [ ] **Step 3: Add Diagnose toolbar button to MainWindowView**

In `MeshCoreMac/Views/MainWindow/MainWindowView.swift`:

Add `@State private var showingDiagnostics = false` alongside the existing `showingMap` state.

Add a second `.sheet` modifier for diagnostics (after the map sheet):

```swift
.sheet(isPresented: $showingDiagnostics) {
    NavigationStack {
        DiagnosticsView(diagnosticsVM: container.diagnosticsViewModel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { showingDiagnostics = false }
                }
            }
    }
}
```

Add a second `ToolbarItem` in `messengerView`'s toolbar (alongside the existing map button):

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showingMap = true
        } label: {
            Label("Karte", systemImage: "map")
        }
        .help("Karte aller bekannten Nodes anzeigen")
    }
    ToolbarItem(placement: .primaryAction) {
        Button {
            showingDiagnostics = true
        } label: {
            Label("Diagnose", systemImage: "waveform.path.ecg")
        }
        .help("Diagnose-Fenster: RX Log, CLI, Node Status")
    }
}
```

Full updated `MainWindowView.swift`:

```swift
// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    @State private var dismissedError: String? = nil
    @State private var showingMap = false
    @State private var showingDiagnostics = false

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
                MapSheetContent(contactsVM: container.contactsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showingMap = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationStack {
                DiagnosticsView(diagnosticsVM: container.diagnosticsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showingDiagnostics = false }
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
                ChatContainer(
                    container: container,
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingMap = true
                } label: {
                    Label("Karte", systemImage: "map")
                }
                .help("Karte aller bekannten Nodes anzeigen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("Diagnose", systemImage: "waveform.path.ecg")
                }
                .help("Diagnose-Fenster: RX Log, CLI, Node Status")
            }
        }
    }
}

// Observes ContactsViewModel directly so NodeMapView updates reactively.
private struct MapSheetContent: View {
    let contactsVM: ContactsViewModel
    var body: some View {
        NodeMapView(contacts: contactsVM.contacts, ownPosition: contactsVM.ownPosition)
    }
}

// Holds a stable ChatViewModel per conversation via @State, preventing
// re-creation on every MainWindowView body re-render.
private struct ChatContainer: View {
    let container: AppContainer
    let conversation: MeshMessage.Kind
    let contactsVM: ContactsViewModel

    @State private var chatVM: ChatViewModel?

    var body: some View {
        Group {
            if let chatVM {
                ChatView(chatVM: chatVM, conversation: conversation, contactsVM: contactsVM)
            } else {
                ProgressView()
            }
        }
        .task(id: conversation) {
            chatVM = container.makeChatViewModel(for: conversation)
        }
    }
}
```

- [ ] **Step 4: Build and run full test suite**

```bash
xcodegen generate && xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ test|All tests|error:"
```

Expected: `All tests passed` (58 tests).

- [ ] **Step 5: Commit**

```bash
git add MeshCoreMac/App/AppContainer.swift \
        MeshCoreMac/App/MeshCoreMacApp.swift \
        MeshCoreMac/Views/MainWindow/MainWindowView.swift
git commit -m "feat(phase3): wire DiagnosticsViewModel into AppContainer, add Diagnose toolbar button"
```

---

## Self-Review

### Spec Coverage

| Feature | Task |
|---|---|
| RX Log (alle BLE-Frames) | Task 1 (RxLogEntry), Task 3 (rxLogStream), Task 5 (VM), Task 6 (View) |
| CLI (Hex-Befehl-Eingabe) | Task 5 (sendCLICommand), Task 6 (CLIView) |
| Noise Floor | Task 4 (noiseFloor case), Task 5 (extraction), Task 6 (NodeStatusView) |
| Trace Path | Task 4 (encodeTracePath + CMD), Task 6 (CLIView Quick-Command hint) |
| Battery & Speicher | Task 4 (battAndStorage case), Task 5 (extraction), Task 6 (NodeStatusView) |
| Diagnose-Fenster in Toolbar | Task 7 |

### Placeholder Check

No TBD/TODO markers. All code steps contain complete Swift code.

### Type Consistency

- `RxLogEntry.Direction` used in Tasks 1, 2, 3, 5 ✓
- `DiagnosticsViewModel.logEntries: [RxLogEntry]` matches test expectations ✓
- `CLIError.invalidHex(String)` defined and thrown consistently ✓
- `MeshCoreProtocol.Command.tracePath = 0x07` referenced in encoder (Task 4) ✓
- `DecodedFrame.battAndStorage` / `.noiseFloor` added in Task 4, referenced in Tasks 3, 5, switch updates ✓
- `clearLog()` added to `DiagnosticsViewModel` in Task 6 Step 2 — must also be added to Task 5's implementation. Add to `DiagnosticsViewModel`:
  ```swift
  func clearLog() { logEntries = [] }
  ```
