// MeshCoreMac/ViewModels/SidebarViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class SidebarViewModel {
    var channels: [MeshChannel] = []
    var contacts: [MeshContact] = []
    var selectedConversation: MeshMessage.Kind? = nil

    init() {
        loadDefaultChannels()
    }

    private func loadDefaultChannels() {
        channels = [MeshChannel(id: 0, name: "Allgemein")]
    }

    func addChannel(_ channel: MeshChannel) {
        if !channels.contains(channel) {
            channels.append(channel)
        }
    }

    func updateContact(_ contact: MeshContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
    }

    func selectConversation(_ kind: MeshMessage.Kind) {
        selectedConversation = kind
    }
}
