// MeshCoreMac/Views/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let container: AppContainer
    let openWindow: () -> Void

    var body: some View {
        let state = container.connectionViewModel.connectionState

        Label(state.displayName, systemImage: statusIcon(for: state))
            .foregroundStyle(statusColor(for: state))

        Divider()

        Text("Letzte Nachrichten")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("— keine neuen —")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        Divider()

        Button("Fenster öffnen") { openWindow() }

        Button("Diagnose / Event-Log") {}
            .disabled(true)  // wird in Task 12 implementiert

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
        case .ready:                             return "circle.fill"
        case .scanning, .connecting, .connected: return "circle.dotted"
        case .disconnected:                      return "circle.slash"
        case .failed:                            return "exclamationmark.circle"
        }
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .ready:                             return .green
        case .scanning, .connecting, .connected: return .yellow
        case .disconnected:                      return .red
        case .failed:                            return .red
        }
    }
}
