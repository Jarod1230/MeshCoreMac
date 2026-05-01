// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    var body: some View {
        Group {
            if container.connectionViewModel.connectionState.isConnectedOrReady {
                messengerView
            } else {
                PairingView(connectionVM: container.connectionViewModel)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private var messengerView: some View {
        NavigationSplitView {
            SidebarView(
                sidebarVM: container.sidebarViewModel,
                connectionVM: container.connectionViewModel
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let conversation = container.sidebarViewModel.selectedConversation {
                // Platzhalter — wird in Task 11 durch ChatView ersetzt
                Text("Chat für \(conversationTitle(conversation))")
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "Keine Konversation gewählt",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Wähle einen Kanal oder Kontakt in der Sidebar.")
                )
            }
        }
    }

    private func conversationTitle(_ kind: MeshMessage.Kind) -> String {
        switch kind {
        case .channel(let idx): return "Kanal \(idx)"
        case .direct(let id):   return "DM \(id)"
        }
    }
}
