import XCTest
@testable import MeshCoreMac

@MainActor
final class ContactStoreTests: XCTestCase {

    func testSaveAndFetch_roundtripsAllFields() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "a1b2c3d4", name: "Alice",
                                   lastSeen: nil, isOnline: true,
                                   lat: 48.137, lon: 11.575)
        try await store.save(contact)
        let all = try await store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, "a1b2c3d4")
        XCTAssertEqual(all[0].name, "Alice")
        XCTAssertEqual(all[0].isOnline, true)
        XCTAssertEqual(all[0].lat ?? 0, 48.137, accuracy: 0.0001)
        XCTAssertEqual(all[0].lon ?? 0, 11.575, accuracy: 0.0001)
    }

    func testSave_upsertsByPrimaryKey() async throws {
        let store = try ContactStore(inMemory: true)
        var contact = MeshContact(id: "a1b2c3d4", name: "Bob",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        contact.name = "Bob Updated"
        contact.isOnline = true
        contact.lat = 52.52
        contact.lon = 13.405
        try await store.save(contact)
        let all = try await store.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Bob Updated")
        XCTAssertEqual(all[0].lat ?? 0, 52.52, accuracy: 0.001)
        XCTAssertTrue(all[0].isOnline)
    }

    func testFetchById_returnsNilForMissing() async throws {
        let store = try ContactStore(inMemory: true)
        let result = try await store.fetch(id: "00000000")
        XCTAssertNil(result)
    }

    func testFetchById_returnsContact() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "deadbeef", name: "Eve",
                                   lastSeen: nil, isOnline: true,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        let fetched = try await store.fetch(id: "deadbeef")
        XCTAssertEqual(fetched?.name, "Eve")
    }

    func testLastSeen_roundtrips() async throws {
        let store = try ContactStore(inMemory: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let contact = MeshContact(id: "aa11bb22", name: "Dave",
                                   lastSeen: date, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        let all = try await store.fetchAll()
        let delta = abs((all[0].lastSeen?.timeIntervalSince1970 ?? 0) - 1_700_000_000)
        XCTAssertLessThan(delta, 1.0)
    }

    func testDelete_removesContact() async throws {
        let store = try ContactStore(inMemory: true)
        let contact = MeshContact(id: "cafe1234", name: "Chuck",
                                   lastSeen: nil, isOnline: false,
                                   lat: nil, lon: nil)
        try await store.save(contact)
        try await store.delete(id: "cafe1234")
        let all = try await store.fetchAll()
        XCTAssert(all.isEmpty)
    }
}
