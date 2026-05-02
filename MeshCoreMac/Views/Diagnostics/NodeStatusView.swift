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
                    Task { try? await diagnosticsVM.requestNodeStatus() }
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
