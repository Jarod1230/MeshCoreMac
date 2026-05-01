// MeshCoreMac/Services/ContactStore.swift
import GRDB
import Foundation

final class ContactStore: Sendable {
    private let dbQueue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport
                .appendingPathComponent("MeshCoreMac", isDirectory: true)
                .appendingPathComponent("contacts.sqlite")
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            dbQueue = try DatabaseQueue(path: dbURL.path)
        }
        try runMigrations()
    }

    // MARK: - Migrations
    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_contacts") { db in
            try db.create(table: ContactRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lastSeen", .double)
                t.column("isOnline", .boolean).notNull()
                t.column("lat", .double)
                t.column("lon", .double)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Write
    func save(_ contact: MeshContact) async throws {
        let record = ContactRecord(from: contact)
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    // MARK: - Read
    func fetchAll() async throws -> [MeshContact] {
        try await dbQueue.read { db in
            try ContactRecord.fetchAll(db).map { $0.toMeshContact() }
        }
    }

    func fetch(id: String) async throws -> MeshContact? {
        try await dbQueue.read { db in
            try ContactRecord.fetchOne(db, key: id)?.toMeshContact()
        }
    }

    func delete(id: String) async throws {
        try await dbQueue.write { db in
            _ = try ContactRecord.deleteOne(db, key: id)
        }
    }
}
