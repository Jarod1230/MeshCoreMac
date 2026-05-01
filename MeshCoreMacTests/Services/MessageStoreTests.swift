// MeshCoreMacTests/Services/MessageStoreTests.swift
import XCTest
import GRDB
@testable import MeshCoreMac

final class MessageStoreTests: XCTestCase {

    var store: MessageStore!

    override func setUp() async throws {
        store = try MessageStore(inMemory: true)
    }

    override func tearDown() async throws {
        store = nil
    }

    func testSaveAndFetch_channelMessage() async throws {
        let msg = MeshMessage(
            id: UUID(),
            kind: .channel(index: 0),
            senderName: "Node-42",
            text: "Hallo",
            timestamp: Date(),
            routing: MeshMessage.Routing(hops: 1, snr: -5.0, routeDisplay: nil),
            deliveryStatus: .delivered,
            isIncoming: true
        )
        try await store.save(msg)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Hallo")
        XCTAssertEqual(fetched[0].routing?.hops, 1)
    }

    func testSaveAndFetch_directMessage() async throws {
        let msg = MeshMessage(
            id: UUID(),
            kind: .direct(contactId: "abc123"),
            senderName: "Node-42",
            text: "Privat",
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sent,
            isIncoming: false
        )
        try await store.save(msg)
        let fetched = try await store.fetchMessages(for: .direct(contactId: "abc123"))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Privat")
    }

    func testFetch_returnsOnlyMatchingConversation() async throws {
        let ch0 = MeshMessage(id: UUID(), kind: .channel(index: 0),
            senderName: "A", text: "Kanal 0", timestamp: Date(),
            routing: nil, deliveryStatus: .delivered, isIncoming: true)
        let ch1 = MeshMessage(id: UUID(), kind: .channel(index: 1),
            senderName: "B", text: "Kanal 1", timestamp: Date(),
            routing: nil, deliveryStatus: .delivered, isIncoming: true)
        try await store.save(ch0)
        try await store.save(ch1)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "Kanal 0")
    }

    func testUpdateDeliveryStatus() async throws {
        let id = UUID()
        let msg = MeshMessage(id: id, kind: .channel(index: 0),
            senderName: "Me", text: "Test", timestamp: Date(),
            routing: nil, deliveryStatus: .sending, isIncoming: false)
        try await store.save(msg)
        try await store.updateDeliveryStatus(messageId: id, status: .delivered)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched[0].deliveryStatus, .delivered)
    }

    func testDeliveryStatus_failed_roundTrip() async throws {
        let id = UUID()
        let msg = MeshMessage(id: id, kind: .channel(index: 0),
            senderName: "Me", text: "Test", timestamp: Date(),
            routing: nil, deliveryStatus: .failed("Timeout"), isIncoming: false)
        try await store.save(msg)
        let fetched = try await store.fetchMessages(for: .channel(index: 0))
        XCTAssertEqual(fetched[0].deliveryStatus, .failed("Timeout"))
    }

    func testUpdateDeliveryStatus_unknownId_throws() async throws {
        let unknownId = UUID()
        do {
            try await store.updateDeliveryStatus(messageId: unknownId, status: .delivered)
            XCTFail("Hätte werfen sollen")
        } catch MessageStoreError.messageNotFound {
            // erwartet
        }
    }
}
