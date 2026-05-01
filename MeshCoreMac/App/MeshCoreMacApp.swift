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
        WindowGroup {
            // Platzhalter — wird in Task 10 durch MainWindowView ersetzt
            Text("MeshCoreMac")
                .onDisappear {
                    appDelegate.switchToAccessoryMode()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MeshCoreMac", systemImage: menuBarIcon) {
            // Platzhalter — wird in Task 8 durch MenuBarView ersetzt
            Button("Fenster öffnen") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
    }

    private var menuBarIcon: String {
        switch container.connectionViewModel.connectionState {
        case .ready:                               return "antenna.radiowaves.left.and.right.circle.fill"
        case .scanning, .connecting, .connected:   return "antenna.radiowaves.left.and.right.circle"
        default:                                   return "antenna.radiowaves.left.and.right.slash"
        }
    }
}
