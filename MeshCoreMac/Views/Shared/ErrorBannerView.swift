// MeshCoreMac/Views/Shared/ErrorBannerView.swift
import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            if let onRetry {
                Button("Erneut", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fehlermeldung schließen")
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.95))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
