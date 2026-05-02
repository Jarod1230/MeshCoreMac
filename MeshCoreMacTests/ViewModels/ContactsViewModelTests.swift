// MeshCoreMacTests/ViewModels/ContactsViewModelTests.swift
import XCTest
import CoreLocation
@testable import MeshCoreMac

@MainActor
final class ContactsViewModelTests: XCTestCase {

    var mockBluetooth: MockBluetoothService!
    var contactStore: ContactStore!
    var vm: ContactsViewModel!

    override func setUp() async throws {
        mockBluetooth = MockBluetoothService()
        contactStore = try ContactStore(inMemory: true)
        vm = ContactsViewModel(contactStore: contactStore, bluetoothService: mockBluetooth)
        await vm.start()
    }

    override func tearDown() async throws {
        vm = nil
        contactStore = nil
        mockBluetooth = nil
    }

    func testNodeAdvert_addsContactToList() async throws {
        mockBluetooth.simulateNodeEvent(
            .nodeAdvert(contactId: "a1b2c3d4", name: "Alice", lat: 48.137, lon: 11.575)
        )
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts.count, 1)
        XCTAssertEqual(vm.contacts[0].name, "Alice")
        XCTAssertTrue(vm.contacts[0].isOnline)
        XCTAssertEqual(vm.contacts[0].lat ?? 0, 48.137, accuracy: 0.001)
    }

    func testNodeAdvert_persistsToStore() async throws {
        mockBluetooth.simulateNodeEvent(
            .nodeAdvert(contactId: "a1b2c3d4", name: "Alice", lat: nil, lon: nil)
        )
        try await waitUntil { !self.vm.contacts.isEmpty }
        let stored = try await contactStore.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "Alice")
    }

    func testContactEvent_addsToList() async throws {
        let contact = MeshContact(id: "dead1234", name: "Bob",
                                   lastSeen: nil, isOnline: true,
                                   lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(contact))
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts[0].name, "Bob")
    }

    func testSelfInfo_setsOwnPosition() async throws {
        mockBluetooth.simulateNodeEvent(
            .selfInfo(nodeId: "aa11bb22", lat: 52.52, lon: 13.405, firmware: "v1.0",
                      radioFrequencyHz: 0, radioBandwidthHz: 0,
                      radioSpreadingFactor: 0, radioCodingRate: 0)
        )
        try await waitUntil { self.vm.ownPosition != nil }
        XCTAssertEqual(vm.ownPosition?.latitude ?? 0, 52.52, accuracy: 0.001)
        XCTAssertEqual(vm.ownPosition?.longitude ?? 0, 13.405, accuracy: 0.001)
    }

    func testStart_loadsPersistedContacts() async throws {
        let contact = MeshContact(id: "cafe1234", name: "Charlie",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await contactStore.save(contact)

        let isolatedMock = MockBluetoothService()
        let newVM = ContactsViewModel(contactStore: contactStore, bluetoothService: isolatedMock)
        await newVM.start()

        XCTAssertEqual(newVM.contacts.count, 1)
        XCTAssertEqual(newVM.contacts[0].name, "Charlie")
    }

    func testUpdateContact_persistsNameChange() async throws {
        var contact = MeshContact(id: "aa11bb22", name: "Dave",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(contact))
        try await waitUntil { !self.vm.contacts.isEmpty }

        contact.name = "Dave Updated"
        await vm.updateContact(contact)

        let stored = try await contactStore.fetchAll()
        XCTAssertEqual(stored.first?.name, "Dave Updated")
        XCTAssertEqual(vm.contacts.first?.name, "Dave Updated")
    }

    func testStart_calledTwice_doesNotOverwriteLiveContacts() async throws {
        mockBluetooth.simulateNodeEvent(
            .nodeAdvert(contactId: "a1b2c3d4", name: "Alice", lat: nil, lon: nil)
        )
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts.count, 1)

        await vm.start()
        XCTAssertEqual(vm.contacts.count, 1, "Second start() call must be a no-op")
    }

    func testContactsEnd_withoutStart_isNoOp() async throws {
        let contact = MeshContact(id: "a1b2c3d4", name: "Alice",
                                   lastSeen: nil, isOnline: true,
                                   lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(contact))
        try await waitUntil { !self.vm.contacts.isEmpty }
        XCTAssertEqual(vm.contacts.count, 1)

        mockBluetooth.simulateNodeEvent(.contactsEnd)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(vm.contacts.count, 1, "contactsEnd without contactsStart must not clear contacts")
    }

    func testContactsStart_twice_resetsBuffer() async throws {
        mockBluetooth.simulateNodeEvent(.contactsStart)
        let c1 = MeshContact(id: "a1b2c3d4", name: "Alice",
                              lastSeen: nil, isOnline: true, lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(c1))
        try await Task.sleep(for: .milliseconds(20))

        mockBluetooth.simulateNodeEvent(.contactsStart)
        let c2 = MeshContact(id: "b2c3d4e5", name: "Bob",
                              lastSeen: nil, isOnline: true, lat: nil, lon: nil)
        mockBluetooth.simulateNodeEvent(.contact(c2))
        mockBluetooth.simulateNodeEvent(.contactsEnd)
        try await waitUntil { self.vm.contacts.contains(where: { $0.id == "b2c3d4e5" }) }

        XCTAssertFalse(vm.contacts.contains(where: { $0.id == "a1b2c3d4" }),
                       "Second contactsStart must discard first buffer (Alice not persisted yet)")
        XCTAssertTrue(vm.contacts.contains(where: { $0.id == "b2c3d4e5" }),
                      "Bob from second sequence must be present")
    }

    // MARK: - Helper

    private func waitUntil(
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timeout waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
