// MeshCoreMac/App/AppContainer.swift
import Foundation

@MainActor
final class AppContainer {
    let bluetoothService: any BluetoothServiceProtocol
    let messageStore: MessageStore
    let contactStore: ContactStore
    let connectionViewModel: ConnectionViewModel
    let sidebarViewModel: SidebarViewModel
    let contactsViewModel: ContactsViewModel
    let diagnosticsViewModel: DiagnosticsViewModel
    let notificationService: NotificationService

    init() throws {
        bluetoothService = MeshCoreBluetoothService()
        messageStore = try MessageStore()
        contactStore = try ContactStore()
        connectionViewModel = ConnectionViewModel(bluetoothService: bluetoothService)
        sidebarViewModel = SidebarViewModel()
        contactsViewModel = ContactsViewModel(contactStore: contactStore, bluetoothService: bluetoothService)
        diagnosticsViewModel = DiagnosticsViewModel(bluetoothService: bluetoothService)
        notificationService = NotificationService()
    }

    func makeChatViewModel(for conversation: MeshMessage.Kind) -> ChatViewModel {
        ChatViewModel(
            bluetoothService: bluetoothService,
            messageStore: messageStore,
            conversation: conversation,
            notificationService: notificationService
        )
    }
}
