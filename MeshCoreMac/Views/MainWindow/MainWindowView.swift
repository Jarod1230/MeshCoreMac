// MeshCoreMac/Views/MainWindow/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    let container: AppContainer

    @State private var dismissedError: String? = nil
    @State private var showingMap = false
    @State private var showingDiagnostics = false

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
                MapSheetContent(contactsVM: container.contactsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showingMap = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationStack {
                DiagnosticsView(diagnosticsVM: container.diagnosticsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { showingDiagnostics = false }
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
                ChatContainer(
                    container: container,
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingMap = true
                } label: {
                    Label("Karte", systemImage: "map")
                }
                .help("Karte aller bekannten Nodes anzeigen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingDiagnostics = true
                } label: {
                    Label("Diagnose", systemImage: "waveform.path.ecg")
                }
                .help("Diagnose-Fenster: RX Log, CLI, Node Status")
            }
        }
    }
}

// Observes ContactsViewModel directly so NodeMapView updates reactively.
private struct MapSheetContent: View {
    let contactsVM: ContactsViewModel
    var body: some View {
        NodeMapView(contacts: contactsVM.contacts, ownPosition: contactsVM.ownPosition)
    }
}

// Holds a stable ChatViewModel per conversation via @State, preventing
// re-creation on every MainWindowView body re-render.
private struct ChatContainer: View {
    let container: AppContainer
    let conversation: MeshMessage.Kind
    let contactsVM: ContactsViewModel

    @State private var chatVM: ChatViewModel?

    var body: some View {
        Group {
            if let chatVM {
                ChatView(chatVM: chatVM, conversation: conversation, contactsVM: contactsVM)
            } else {
                ProgressView()
            }
        }
        .task(id: conversation) {
            chatVM = container.makeChatViewModel(for: conversation)
        }
    }
}
