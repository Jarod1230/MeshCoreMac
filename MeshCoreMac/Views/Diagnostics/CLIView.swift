// MeshCoreMac/Views/Diagnostics/CLIView.swift
import SwiftUI

struct CLIView: View {
    @Bindable var diagnosticsVM: DiagnosticsViewModel
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
