# MeshCoreMac

Native macOS-App zur Kommunikation über das [MeshCore](https://github.com/ripplebiz/MeshCore) Off-Grid-Mesh-Netzwerk. Verbindet sich per Bluetooth Low Energy (BLE) mit einem MeshCore-Node und bietet einen vollständigen Messenger mit Kanal- und Direktnachrichten.

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

## Features (Phase 1)

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

---

## Architektur

```
┌─────────────────────────────────┐
│         SwiftUI Views           │
├─────────────────────────────────┤
│      @Observable ViewModels     │
├─────────────────────────────────┤
│   MeshCoreBluetoothService      │  CoreBluetooth, @MainActor
│   MeshCoreProtocolService       │  Frame-Encode/Decode
│   MessageStore                  │  SQLite via GRDB
└─────────────────────────────────┘
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
├── Models/                 # ConnectionState, MeshMessage, MeshChannel, MeshContact
├── Services/               # BLE-Service, Protocol-Parser, MessageStore
├── ViewModels/             # ConnectionViewModel, SidebarViewModel, ChatViewModel
└── Views/
    ├── MainWindow/         # MainWindowView, SidebarView, ChatView, MessageBubbleView
    ├── MenuBar/            # MenuBarView
    ├── Onboarding/         # PairingView
    ├── Settings/           # SettingsView (Backup/Restore)
    └── Shared/             # ErrorBannerView
```

### MeshCore-Protokoll (Companion-Modus)

Die App kommuniziert über das Nordic UART Service (NUS) BLE-Profil:

| UUID | Funktion |
|---|---|
| `6E400001-...` | Service UUID |
| `6E400002-...` | TX Characteristic (App → Node) |
| `6E400003-...` | RX Characteristic (Node → App, Notify) |

Beim Verbindungsaufbau sendet die App automatisch `APP_START` (0x01) und `DEVICE_QUERY` (0x16).

---

## Tests

```bash
xcodegen generate
xcodebuild test -project MeshCoreMac.xcodeproj -scheme MeshCoreMac \
  -destination 'platform=macOS'
```

25 Tests in 6 Test-Suiten:

| Suite | Tests |
|---|---|
| `ConnectionViewModelTests` | 3 |
| `ChatViewModelTests` | 4 |
| `MeshCoreProtocolServiceTests` | 6 |
| `MeshMessageTests` | 6 |
| `MessageStoreTests` | 6 |
| `MeshCoreMacTests` | Sanity-Check |

---

## Roadmap

| Phase | Inhalt | Status |
|---|---|---|
| **1** | BLE-Verbindung + Messenger | **Abgeschlossen** |
| 2 | Kontakte & Karte | Geplant |
| 3 | Netzwerk-Tools (RX Log, Trace Path, Noise Floor, CLI) | Geplant |
| 4 | Node-Konfiguration & Remote-Admin | Geplant |

### Bekannte Grenzen (Phase 1)

- Kein USB/Serial-Anschluss (nur BLE)
- Nur ein Node gleichzeitig
- "Diagnose / Event-Log" in der Menüleiste ist noch nicht implementiert (Phase 3)
- Node-Positionen und Karte fehlen (Phase 2)

---

## Lizenz

Privates Projekt. Kein offizielles Release.
