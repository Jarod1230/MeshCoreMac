// MeshCoreMac/Views/Diagnostics/RxLogView.swift
import SwiftUI

struct RxLogView: View {
    let diagnosticsVM: DiagnosticsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RX Log")
                    .font(.headline)
                Spacer()
                Text("\(diagnosticsVM.logEntries.count) Einträge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Leeren") { diagnosticsVM.clearLog() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(diagnosticsVM.logEntries) { entry in
                            RxLogRowView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: diagnosticsVM.logEntries.count) { _, _ in
                    if let last = diagnosticsVM.logEntries.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct RxLogRowView: View {
    let entry: RxLogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.direction.rawValue)
                .foregroundStyle(entry.direction == .incoming ? Color.blue : Color.orange)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 12)
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                if let decoded = entry.decoded {
                    Text(decoded)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
