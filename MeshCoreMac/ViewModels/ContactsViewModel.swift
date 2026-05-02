// MeshCoreMac/ViewModels/ContactsViewModel.swift
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class ContactsViewModel {
    private(set) var contacts: [MeshContact] = []
    private(set) var ownPosition: CLLocationCoordinate2D? = nil

    private let contactStore: ContactStore
    private let bluetoothService: any BluetoothServiceProtocol

    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?
    private var pendingContacts: [MeshContact] = []
    private var collectingContacts = false
    private var started = false

    init(contactStore: ContactStore, bluetoothService: any BluetoothServiceProtocol) {
        self.contactStore = contactStore
        self.bluetoothService = bluetoothService
    }

    func start() async {
        guard !started else { return }
        started = true
        contacts = (try? await contactStore.fetchAll()) ?? []
        startListening()
    }

    func updateContact(_ contact: MeshContact) async {
        try? await contactStore.save(contact)
        upsert(contact)
    }

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task {
            for await event in self.bluetoothService.nodeEventStream {
                guard !Task.isCancelled else { break }
                await self.handleNodeEvent(event)
            }
        }
    }

    private func handleNodeEvent(_ frame: DecodedFrame) async {
        switch frame {
        case .selfInfo(_, let lat, let lon, _):
            if let lat = lat, let lon = lon {
                ownPosition = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        case .nodeAdvert(let contactId, let name, let lat, let lon):
            var c = contacts.first(where: { $0.id == contactId })
                ?? MeshContact(id: contactId, name: name ?? contactId,
                               lastSeen: nil, isOnline: false, lat: nil, lon: nil)
            c.isOnline = true
            c.lastSeen = Date()
            if let name = name { c.name = name }
            if let lat = lat { c.lat = lat }
            if let lon = lon { c.lon = lon }
            try? await contactStore.save(c)
            upsert(c)
        case .contact(let c):
            try? await contactStore.save(c)
            if collectingContacts {
                // Buffer during GET_CONTACTS sequence; list replaced on contactsEnd
                if let idx = pendingContacts.firstIndex(where: { $0.id == c.id }) {
                    pendingContacts[idx] = c
                } else {
                    pendingContacts.append(c)
                }
            } else {
                upsert(c)
            }
        case .contactsStart:
            pendingContacts = []
            collectingContacts = true
        case .contactsEnd:
            if collectingContacts {
                // Merge GET_CONTACTS list: replace known list, keep ADVERT-only nodes
                let listedIds = Set(pendingContacts.map { $0.id })
                let advertOnly = contacts.filter { !listedIds.contains($0.id) }
                contacts = pendingContacts + advertOnly
                collectingContacts = false
                pendingContacts = []
            }
        case .newChannelMessage, .newDirectMessage, .messageAck,
             .battAndStorage, .noiseFloor:
            break
        }
    }

    private func upsert(_ contact: MeshContact) {
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        } else {
            contacts.append(contact)
        }
    }

    deinit { listenerTask?.cancel() }  // Task.cancel() ist nonisolated — erlaubt
}
