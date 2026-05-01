// MeshCoreMac/Views/MainWindow/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    let sidebarVM: SidebarViewModel
    let connectionVM: ConnectionViewModel

    var body: some View {
        List(selection: Binding(
            get: { sidebarVM.selectedConversation.map(ConversationID.init) },
            set: { id in
                if let kind = id?.kind { sidebarVM.selectConversation(kind) }
            }
        )) {
            Section("Kanäle") {
                ForEach(sidebarVM.channels) { channel in
                    Label("# \(channel.name)", systemImage: "number")
                        .tag(ConversationID(kind: .channel(index: channel.id)))
                }
            }

            if !sidebarVM.contacts.isEmpty {
                Section("Direkt") {
                    ForEach(sidebarVM.contacts) { contact in
                        HStack {
                            Label(contact.name, systemImage: "person.fill")
                            Spacer()
                            Circle()
                                .fill(contact.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                        }
                        .tag(ConversationID(kind: .direct(contactId: contact.id)))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionVM.connectionState.isConnectedOrReady ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(connectionVM.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct ConversationID: Hashable {
    let kind: MeshMessage.Kind
}
