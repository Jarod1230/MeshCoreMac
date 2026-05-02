// MeshCoreMac/Views/MainWindow/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    let sidebarVM: SidebarViewModel
    let connectionVM: ConnectionViewModel
    let contactsVM: ContactsViewModel

    @State private var selectedContactForDetail: MeshContact? = nil

    var body: some View {
        List(selection: Binding(
            get: { sidebarVM.selectedConversation },
            set: { kind in
                if let kind { sidebarVM.selectConversation(kind) }
            }
        )) {
            Section("Kanäle") {
                ForEach(sidebarVM.channels) { channel in
                    Label("# \(channel.name)", systemImage: "number")
                        .tag(MeshMessage.Kind.channel(index: channel.id))
                }
            }

            if !contactsVM.contacts.isEmpty {
                Section("Direkt") {
                    ForEach(contactsVM.contacts) { contact in
                        HStack {
                            Label(contact.name, systemImage: "person.fill")
                                .tag(MeshMessage.Kind.direct(contactId: contact.id))
                            Spacer()
                            Circle()
                                .fill(contact.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Button {
                                selectedContactForDetail = contact
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
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
        .sheet(item: $selectedContactForDetail) { contact in
            NavigationStack {
                ContactDetailView(contact: contact) { updated in
                    Task { await contactsVM.updateContact(updated) }
                }
            }
        }
    }
}
