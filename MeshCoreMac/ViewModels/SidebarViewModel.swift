// MeshCoreMac/ViewModels/SidebarViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class SidebarViewModel {
    var channels: [MeshChannel] = []
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

    func selectConversation(_ kind: MeshMessage.Kind) {
        selectedConversation = kind
    }
}
