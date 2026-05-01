// MeshCoreMac/App/AppContainer.swift
import Foundation

@MainActor
final class AppContainer {
    let bluetoothService: MeshCoreBluetoothService
    let messageStore: MessageStore
    let connectionViewModel: ConnectionViewModel
    let sidebarViewModel: SidebarViewModel
    let notificationService: NotificationService

    init() throws {
        bluetoothService = MeshCoreBluetoothService()
        messageStore = try MessageStore()
        connectionViewModel = ConnectionViewModel(bluetoothService: bluetoothService)
        sidebarViewModel = SidebarViewModel()
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
