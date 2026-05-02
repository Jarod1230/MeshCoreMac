# MeshCoreMac

Native macOS-App zur Kommunikation über das [MeshCore](https://github.com/ripplebiz/MeshCore) Off-Grid-Mesh-Netzwerk. Verbindet sich per Bluetooth Low Energy (BLE) mit einem MeshCore-Node und bietet einen vollständigen Messenger mit Kanal- und Direktnachrichten, einer Kontaktkarte und Netzwerk-Diagnosewerkzeugen.

Privacy-first: keine Telemetrie, kein Cloud-Sync, alle Daten lokal.

---

## Voraussetzungen

- macOS 15.0 oder neuer
- [Xcode](https://developer.apple.com/xcode/) 16 oder neuer
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Ein MeshCore-Node mit BLE-Gateway-Funktion

## Installation & Build

```bash
git clone https://github.com/Jarod1230/MeshCoreMac.git
cd MeshCoreMac
xcodegen generate
open MeshCoreMac.xcodeproj
```

Dann in Xcode: **Run** (⌘R).

> Die App signiert nicht (Code Signing deaktiviert für Entwicklung). Für Testflüge auf echtem Hardware ggf. Team-ID in `project.yml` eintragen.

---

## Features

### Verbindung
- **BLE-Verbindung** zu einem MeshCore-Node (Nordic UART Service)
- Automatisches Reconnect alle 10 Sekunden bei Verbindungsabbruch
- Letzter verbundener Node wird gespeichert und beim Start automatisch verbunden
- Verbindungsstatus immer sichtbar: Menüleisten-Icon + Banner im Fenster

### Messenger
- **Kanäle** und **Direktnachrichten** in einer Sidebar
- **Tech-Badges** unter jeder Nachricht: Hops, SNR (dB), Route via Repeater
- **Zustellstatus**: Wird gesendet → Gesendet → Zugestellt ✓
- Zeichenlimit: 133 Bytes (MeshCore-Protokollgrenze) mit Live-Zähler
- Senden per Klick oder ⌘↩

### Kontakte & Karte
- **Kontaktliste** aus dem Mesh: live aktualisiert via `ADVERT`- und `GET_CONTACTS`-Frames
- **Kontakt-Detail-Sheet**: Name bearbeiten, Online-Status, letzte Aktivität, GPS-Position
- **Node-Karte**: zeigt alle Nodes mit bekannter GPS-Position auf einer Kartenansicht
- Offline-persistente Kontakte (SQLite) — bleiben über Neustarts erhalten

### Netzwerk-Diagnose
- **RX Log**: Live-Anzeige aller BLE-Frames (eingehend ↓ und ausgehend ↑) mit Zeitstempel, Hex-Dump und dekodiertem Frame-Typ; automatischer Scroll, max. 200 Einträge
- **CLI**: Rohe Hex-Bytes direkt an den Node senden; Schnellbefehle für häufige Commands (GET_CONTACTS, DEVICE_QUERY, BATT_STORAGE, APP_START); Befehlsverlauf mit Tap-to-reuse
- **Node Status**: Batterie-Ladestand (%), belegter und freier Speicher, RSSI und Noise Floor in dBm

### System-Integration
- **Menüleisten-App**: läuft im Hintergrund ohne Dock-Icon, öffnet Fenster bei Bedarf
- **macOS-Benachrichtigungen** bei eingehenden Nachrichten
- Automatischer Light/Dark-Mode

### Datenspeicherung
- Lokale SQLite-Datenbank via GRDB (WAL-sicher)
- **Manuelles Backup**: Einstellungen → Backup erstellen (`.meshcorebackup`)
- **Wiederherstellen**: Einstellungen → Backup wiederherstellen

### Fehlerbehandlung
- Verbindungsfehler → Banner mit Retry-Button
- Sendefehler → Badge „Nicht zugestellt ⚠️"
- Fehlende Bluetooth-Berechtigung → erklärender Dialog
- CLI-Fehler → Inline-Fehlermeldung

---

## Architektur

```
┌──────────────────────────────────────────────┐
│                  SwiftUI Views               │
│  MainWindow · Map · Diagnostics · Settings   │
├──────────────────────────────────────────────┤
│             @Observable ViewModels           │
│  Connection · Sidebar · Chat · Contacts      │
│  Diagnostics                                 │
├──────────────────────────────────────────────┤
│           MeshCoreBluetoothService           │  CoreBluetooth, @MainActor
│  incomingFrames ──────────────► ChatVM       │
│  nodeEventStream ─────────────► ContactsVM  │
│  rxLogStream ─────────────────► DiagnosticsVM│
├──────────────────────────────────────────────┤
│           MeshCoreProtocolService            │  Frame-Encode/Decode
│           MessageStore · ContactStore        │  SQLite via GRDB
└──────────────────────────────────────────────┘
```

**Tech-Stack:**
- Swift 6 (strict concurrency)
- SwiftUI + MVVM + `@Observable`
- CoreBluetooth (`@preconcurrency`-Delegates, `AsyncStream`)
- [GRDB 6](https://github.com/groue/GRDB.swift) für SQLite
- UserNotifications
- xcodegen für Projekt-Generierung

### Paketstruktur

```
MeshCoreMac/
├── App/                    # Entry Point, AppDelegate, AppContainer, NotificationService
├── Models/                 # ConnectionState, MeshMessage, MeshChannel, MeshContact, RxLogEntry
├── Services/               # BLE-Service, Protocol-Parser, MessageStore, ContactStore
├── ViewModels/             # ConnectionViewModel, SidebarViewModel, ChatViewModel,
│                           # ContactsViewModel, DiagnosticsViewModel
└── Views/
    ├── MainWindow/         # MainWindowView, SidebarView, ChatView, MessageBubbleView
    ├── Map/                # NodeMapView
    ├── Diagnostics/        # DiagnosticsView, RxLogView, CLIView, NodeStatusView
    ├── MenuBar/            # MenuBarView
    ├── Onboarding/         # PairingView
    ├── Settings/           # SettingsView (Backup/Restore)
    └── Shared/             # ErrorBannerView, ContactDetailView
```

### Stream-Fan-out

`MeshCoreBluetoothService` multiplext eingehende BLE-Frames in drei unabhängige `AsyncStream`s — jeder mit genau einem Consumer:

| Stream | Consumer | Inhalt |
|---|---|---|
| `incomingFrames` | `ChatViewModel` | Rohe `Data`-Frames für Nachrichten |
| `nodeEventStream` | `ContactsViewModel` | Dekodierte Node-Ereignisse (ADVERT, CONTACT, …) |
| `rxLogStream` | `DiagnosticsViewModel` | Alle Frames (ein- & ausgehend) als `RxLogEntry` |

### MeshCore-Protokoll (Companion-Modus)

Die App kommuniziert über das Nordic UART Service (NUS) BLE-Profil:

| UUID | Funktion |
|---|---|
| `6E400001-…` | Service UUID |
| `6E400002-…` | TX Characteristic (App → Node) |
| `6E400003-…` | RX Characteristic (Node → App, Notify) |

Beim Verbindungsaufbau sendet die App automatisch `APP_START` (0x01), `DEVICE_QUERY` (0x16) und `GET_CONTACTS` (0x04).

Unterstützte Response-Codes:

| Code | Name | Verarbeitung |
|---|---|---|
| `0x05` / `0x0D` | SELF_INFO / DEVICE_INFO | Eigene Node-ID, Position, Firmware |
| `0x02–0x04` | CONTACTS_START/CONTACT/END | Kontaktliste |
| `0x07` / `0x08` | CONTACT_MSG / CHANNEL_MSG | Direktnachrichten / Kanalnachrichten |
| `0x0C` | BATT_AND_STORAGE | Batterie %, Speicher belegt/frei |
| `0x80` / `0x81` | ADVERT / PATH_UPDATED | Node-Ankündigungen mit Position |
| `0x87` | STATUS_RESPONSE | RSSI + Noise Floor |

---

## Tests

```bash
xcodegen generate
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS'
```

59 Tests in 8 Test-Suiten:

| Suite | Tests |
|---|---|
| `ConnectionViewModelTests` | 4 |
| `ChatViewModelTests` | 6 |
| `ContactsViewModelTests` | 9 |
| `DiagnosticsViewModelTests` | 10 |
| `MeshCoreProtocolServiceTests` | 15 |
| `MeshMessageTests` | 6 |
| `MessageStoreTests` | 5 |
| `MeshCoreMacTests` | 1 (Sanity) |

---

## Roadmap

| Phase | Inhalt | Status |
|---|---|---|
| **1** | BLE-Verbindung + Messenger | **Abgeschlossen** |
| **2** | Kontakte & Karte | **Abgeschlossen** |
| **3** | Netzwerk-Tools (RX Log, CLI, Noise Floor, Batterie) | **Abgeschlossen** |
| 4 | Node-Konfiguration & Remote-Admin | Geplant |

---

## Lizenz

Privates Projekt. Kein offizielles Release.
