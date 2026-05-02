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
