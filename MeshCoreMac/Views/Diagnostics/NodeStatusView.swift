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
                            ProgressView(value: Double(batt), total: 100).frame(width: 80)
                            Text("\(batt)%")
                                .monospacedDigit()
                            if let mv = diagnosticsVM.voltageMillivolts {
                                Text("(\(String(format: "%.2f", Double(mv)/1000))V)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    LabeledContent("Batterie", value: "–")
                }
                if let usedKB = diagnosticsVM.storageUsedKB,
                   let totalKB = diagnosticsVM.storageTotalKB {
                    LabeledContent("Belegt", value: "\(usedKB) KB")
                    LabeledContent("Gesamt", value: "\(totalKB) KB")
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


}
