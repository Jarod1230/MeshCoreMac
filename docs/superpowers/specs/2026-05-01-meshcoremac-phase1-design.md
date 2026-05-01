# MeshCoreMac — Phase 1: Verbindungsschicht & Messenger

**Datum:** 2026-05-01  
**Scope:** Phase 1 von 4 (Connection Layer + Messenger MVP)  
**Zielplattform:** macOS 26 (Tahoe)

---

## Überblick

Native macOS-App für die Kommunikation über das MeshCore Off-Grid-Mesh-Netzwerk. Phase 1 liefert den funktionalen Kern: BLE-Verbindung zu einem MeshCore-Node und einen vollständigen Messenger mit technischen Metadaten pro Nachricht.

Die App ist privacy-first: keine Telemetrie, keine Cloud-Synchronisation, alle Daten lokal.

---

## Phasen-Übersicht (Gesamtprojekt)

| Phase | Inhalt |
|---|---|
| **1 (diese Spec)** | BLE-Verbindung + Messenger |
| 2 | Kontakte & Karte |
| 3 | Netzwerk-Tools (RX Log, Noise Floor, Trace Path, CLI) |
| 4 | Node-Konfiguration & Remote-Admin |

---

## Zielgruppe

Funkamateure, Off-Grid-Kommunikations-Enthusiasten und technisch versierte Nutzer, die einen MeshCore-Node als Gateway ins Mesh verwenden.

---

## Architektur

### Schichtenmodell

```
┌─────────────────────────────────┐
│         SwiftUI Views           │
├─────────────────────────────────┤
│      @Observable ViewModels     │
├─────────────────────────────────┤
│   MeshCoreBluetoothService      │  Swift Actor
│   MeshCoreProtocolService       │  Frame-Parser
│   MessageStore                  │  SQLite via GRDB
└─────────────────────────────────┘
```

### Technologie-Stack

- **SwiftUI** — UI-Framework
- **Swift Concurrency** — async/await, AsyncStream, Actors
- **CoreBluetooth** — BLE-Verbindung
- **GRDB** — SQLite-Wrapper für Nachrichtenpersistenz
- **UserNotifications** — macOS-Systembenachrichtigungen

### Paketstruktur

```
MeshCoreMac/
├── App/
│   ├── MeshCoreMacApp.swift       # App-Entry, MenuBar-Setup
│   └── AppDelegate.swift
├── Services/
│   ├── MeshCoreBluetoothService.swift
│   ├── MeshCoreProtocolService.swift
│   └── MessageStore.swift
├── ViewModels/
│   ├── ConnectionViewModel.swift
│   ├── ChatViewModel.swift
│   └── SidebarViewModel.swift
├── Views/
│   ├── MainWindow/
│   │   ├── MainWindowView.swift
│   │   ├── SidebarView.swift
│   │   └── ChatView.swift
│   ├── Onboarding/
│   │   └── PairingView.swift
│   └── MenuBar/
│       └── MenuBarView.swift
└── Models/
    ├── MeshMessage.swift
    ├── MeshChannel.swift
    ├── MeshContact.swift
    └── ConnectionState.swift
```

---

## BLE-Verbindungsschicht

### Verbindungsablauf

1. App startet → `MeshCoreBluetoothService` beginnt Scan nach MeshCore Service-UUID
2. Gefundene Geräte werden als Liste im Pairing-View angezeigt
3. Nutzer wählt ein Gerät → Verbindung wird aufgebaut
4. Nach Verbindung: automatisch `APP_START` + `DEVICE_QUERY` senden
5. Letzter verbundener Node (UUID) wird in `UserDefaults` gespeichert → automatisches Reconnect beim nächsten Start

### Verbindungszustände

```
disconnected → scanning → connecting → connected → ready
                                    ↘ failed (mit Fehlerdetail)
```

### Reconnect-Verhalten

Bei Verbindungsabbruch versucht die App automatisch alle 10 Sekunden erneut zu verbinden. Der Nutzer sieht den Zustand jederzeit im Menüleisten-Icon und im Banner.

### Menüleisten-Statusindikator

| Icon | Bedeutung |
|---|---|
| 🟢 | Verbunden und bereit |
| 🟡 | Verbinde / suche Node |
| 🔴 | Verbindung getrennt |

---

## Messenger

### UI-Layout

Zweispaltig: linke Sidebar + rechter Chat-Bereich. Folgt automatisch dem System-Appearance (Light/Dark Mode).

```
┌──────────────────┬────────────────────────────────┐
│  Sidebar         │  Chat-Bereich                  │
│                  │                                │
│  ● Kanäle        │  [Kanal-Header + Node-Status]  │
│    # allgemein   │                                │
│    # notfall     │  Node-42 · vor 2 Min           │
│                  │  ╭─────────────────────╮       │
│  ● Direkt        │  │ Nachrichtentext      │       │
│    Node-42  🟢   │  ╰─────────────────────╯       │
│    Repeater-7 🟡 │  3 Hops · SNR −8dB · via R-7  │
│                  │                                │
│                  │  ╭──────────────────────╮ [↑] │
│                  │  │ Nachricht eingeben…   │     │
└──────────────────┴────────────────────────────────┘
```

### Nachrichten-Features

- **Tech-Badges** unter jeder Nachricht: Hops, SNR in dBm, Route (via welcher Repeater)
- **Zustellstatus:** „Gesendet" → „Zugestellt ✓" sobald ACK vom Node kommt
- **Zeichenlimit:** 133 Zeichen (MeshCore-Protokollgrenze) mit Live-Zähler
- **System-Events** (z.B. Node verbunden/getrennt) als zentrierte Trennzeilen im Chat
- **Kanäle & Direktnachrichten** im selben Chat-Bereich, Sidebar wechselt den Kontext

### Datenfluss

```
BLE Frame → MeshCoreProtocolService (dekodiert) → MeshMessage
         → MessageStore (speichert) → ChatViewModel (AsyncStream)
         → ChatView (UI aktualisiert)
```

---

## Datenspeicherung

- **Lokal:** SQLite-Datenbank via GRDB im App-Support-Verzeichnis
- **Kein automatischer Cloud-Sync** — privacy-first
- **Manuelles Backup:** Einstellungen → „Backup erstellen" exportiert die DB als `.meshcorebackup`-Datei an einen vom Nutzer gewählten Ort
- **Wiederherstellen:** Einstellungen → „Backup wiederherstellen" importiert die Datei

---

## Hintergrundbetrieb & Menüleiste

- **Activation Policy Switching:** Wenn das Fenster geöffnet ist, erscheint die App normal im Dock (`.regular`). Wenn der Nutzer das Fenster über den roten Schließen-Button schließt, verschwindet das Dock-Icon und die App läuft weiterhin als reine Menüleisten-App (`.accessory`)
- `NSStatusItem` (Menüleisten-Icon) bleibt immer sichtbar
- Menü-Inhalt:

```
● Verbunden: Node-42
─────────────────
  Fenster öffnen
  Letzte Nachrichten (3)
─────────────────
  Diagnose / Event-Log
  Verbindung trennen
  MeshCoreMac beenden
```

- **Systembenachrichtigungen** bei neuen Nachrichten: Absender + Vorschau, Klick öffnet Fenster beim betreffenden Kanal

---

## Fehlerbehandlung

Alle Fehler werden dem Nutzer transparent kommuniziert — kein stilles Schlucken.

| Fehlertyp | Darstellung |
|---|---|
| BLE-Verbindungsverlust | Banner oben im Fenster mit Fehlertext + Retry-Button |
| Node nicht erreichbar | Banner: „Node-42 nicht erreichbar — letzter Kontakt vor X Min" |
| Sendefehler | Badge „Nicht zugestellt ⚠️" + Tipp zeigt Fehlerdetail + Retry |
| Protocol-Fehler | Eintrag im Diagnose-Log (Menüleiste → Diagnose) |
| Kritische Fehler | Modales Dialogfenster mit Beschreibung + Handlungsvorschlag |
| Fehlende BT-Berechtigung | Erklärender Dialog beim Start mit Anleitung |

---

## Nicht im Scope von Phase 1

- USB/Serial-Verbindung (Phase 1 nur BLE)
- Karte & Node-Positionen (Phase 2)
- Netzwerk-Tools: RX Log, Trace Path, Noise Floor (Phase 3)
- Node-Konfiguration & Remote-Admin (Phase 4)
- Mehrere gleichzeitige BLE-Verbindungen

---

## Erfolgskriterien Phase 1

1. App verbindet sich per BLE mit einem MeshCore-Node
2. Kanäle und Direktnachrichten können gelesen und gesendet werden
3. Tech-Badges (Hops, SNR, Route) werden korrekt dargestellt
4. App läuft im Hintergrund, Menüleiste zeigt Verbindungsstatus
5. Neue Nachrichten lösen macOS-Benachrichtigungen aus
6. Nachrichten überleben einen App-Neustart (Persistenz)
7. Manuelles Backup und Wiederherstellen funktioniert
8. Alle Fehler werden dem Nutzer sichtbar dargestellt
