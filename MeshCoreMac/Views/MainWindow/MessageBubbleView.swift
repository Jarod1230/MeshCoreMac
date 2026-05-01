// MeshCoreMac/Views/MainWindow/MessageBubbleView.swift
import SwiftUI

struct MessageBubbleView: View {
    let message: MeshMessage

    var body: some View {
        VStack(alignment: message.isIncoming ? .leading : .trailing, spacing: 4) {
            HStack(spacing: 4) {
                if message.isIncoming {
                    Text(message.senderName)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.isIncoming ? Color(.controlBackgroundColor) : Color.accentColor)
                .foregroundStyle(message.isIncoming ? Color.primary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let routing = message.routing {
                HStack(spacing: 6) {
                    Label("\(routing.hops) Hops", systemImage: "arrow.triangle.swap")
                    Label(String(format: "SNR %.0f dB", routing.snr), systemImage: "waveform")
                    if let route = routing.routeDisplay {
                        Label(route, systemImage: "arrow.right.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            deliveryStatusView
        }
        .frame(maxWidth: .infinity, alignment: message.isIncoming ? .leading : .trailing)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var deliveryStatusView: some View {
        switch message.deliveryStatus {
        case .sending:
            Label("Wird gesendet…", systemImage: "arrow.up.circle")
                .font(.caption2).foregroundStyle(.secondary)
        case .sent:
            Label("Gesendet", systemImage: "checkmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
        case .delivered:
            Label("Zugestellt ✓", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .failed(let reason):
            Label("Nicht zugestellt ⚠️ — \(reason)", systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundStyle(.red)
        }
    }
}
