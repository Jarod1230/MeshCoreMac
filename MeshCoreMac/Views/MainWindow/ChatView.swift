// MeshCoreMac/Views/MainWindow/ChatView.swift
import SwiftUI

struct ChatView: View {
    @Bindable var chatVM: ChatViewModel
    let conversation: MeshMessage.Kind
    let contactsVM: ContactsViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = chatVM.errorMessage {
                ErrorBannerView(message: error) {
                    chatVM.errorMessage = nil
                }
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

                    let count = chatVM.inputText.utf8.count
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
                    chatVM.inputText.utf8.count > MeshCoreProtocol.maxMessageLength
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
        case .channel(let idx):
            return "Kanal \(idx)"
        case .direct(let cid):
            return contactsVM.contacts.first(where: { $0.id == cid })?.name ?? cid
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
