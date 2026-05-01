// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    @State private var dismissedError: String? = nil
    @State private var showingMap = false

    var body: some View {
        Group {
            if container.connectionViewModel.connectionState.isConnectedOrReady {
                messengerView
            } else {
                PairingView(connectionVM: container.connectionViewModel)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .overlay(alignment: .top) {
            if let err = container.connectionViewModel.errorMessage,
               err != dismissedError {
                ErrorBannerView(
                    message: err,
                    onDismiss: { dismissedError = err },
                    onRetry: { container.connectionViewModel.startScan() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: err)
            }
        }
        .onChange(of: container.connectionViewModel.errorMessage) { _, newError in
            if newError != dismissedError {
                dismissedError = nil
            }
        }
        .sheet(isPresented: $showingMap) {
            NavigationStack {
                NodeMapView(
                    contacts: container.contactsViewModel.contacts,
                    ownPosition: container.contactsViewModel.ownPosition
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { showingMap = false }
                    }
                }
            }
        }
    }

    private var messengerView: some View {
        NavigationSplitView {
            SidebarView(
                sidebarVM: container.sidebarViewModel,
                connectionVM: container.connectionViewModel,
                contactsVM: container.contactsViewModel
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let conversation = container.sidebarViewModel.selectedConversation {
                ChatView(
                    chatVM: container.makeChatViewModel(for: conversation),
                    conversation: conversation,
                    contactsVM: container.contactsViewModel
                )
            } else {
                ContentUnavailableView(
                    "Keine Konversation gewählt",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Wähle einen Kanal oder Kontakt in der Sidebar.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingMap = true
                } label: {
                    Label("Karte", systemImage: "map")
                }
                .help("Karte aller bekannten Nodes anzeigen")
            }
        }
    }
}
