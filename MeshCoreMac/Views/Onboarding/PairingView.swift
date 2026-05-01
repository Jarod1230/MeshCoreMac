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
                .disabled(connectionVM.connectionState == .scanning)

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
