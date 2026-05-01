// MeshCoreMac/Views/MainWindow/ChatView.swift
import SwiftUI

struct ChatView: View {
    @State var chatVM: ChatViewModel
    let conversation: MeshMessage.Kind

    var body: some View {
        VStack(spacing: 0) {
            // Fehler-Banner — wird in Task 12 durch ErrorBannerView ersetzt
            if let error = chatVM.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.callout)
                        .lineLimit(2)
                    Spacer()
                    Button { chatVM.errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color(.windowBackgroundColor).opacity(0.95))
                .overlay(alignment: .bottom) { Divider() }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(chatVM.messages) { msg in
                            MessageBubbleView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: chatVM.messages.count) { _, _ in
                    if let last = chatVM.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Nachricht eingeben…", text: $chatVM.inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await trySend() } }

                    let count = chatVM.inputText.count
                    Text("\(count)/\(MeshCoreProtocol.maxMessageLength)")
                        .font(.caption2)
                        .foregroundStyle(count > MeshCoreProtocol.maxMessageLength ? Color.red : Color.secondary)
                }

                Button {
                    Task { await trySend() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(
                    chatVM.inputText.trimmingCharacters(in: .whitespaces).isEmpty ||
                    chatVM.inputText.count > MeshCoreProtocol.maxMessageLength
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .task { await chatVM.loadMessages() }
        .navigationTitle(conversationTitle)
    }

    private var conversationTitle: String {
        switch conversation {
        case .channel(let idx): return "Kanal \(idx)"
        case .direct(let cid):  return cid
        }
    }

    private func trySend() async {
        do {
            try await chatVM.send(text: chatVM.inputText)
        } catch {
            chatVM.errorMessage = error.localizedDescription
        }
    }
}
