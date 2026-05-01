// MeshCoreMac/Services/MessageStore.swift
import GRDB
import Foundation

final class MessageStore: Sendable {
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
                .appendingPathComponent("messages.sqlite")
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
        migrator.registerMigration("v1_create_messages") { db in
            try db.create(table: MessageRecord.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("kindType", .text).notNull()
                t.column("kindValue", .text).notNull()
                t.column("senderName", .text).notNull()
                t.column("text", .text).notNull()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("hops", .integer)
                t.column("snr", .double)
                t.column("routeDisplay", .text)
                t.column("deliveryStatusRaw", .text).notNull()
                t.column("isIncoming", .boolean).notNull()
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Write

    func save(_ message: MeshMessage) async throws {
        let record = MessageRecord(from: message)
        try await dbQueue.write { db in
            try record.save(db)
        }
    }

    func updateDeliveryStatus(messageId: UUID, status: MeshMessage.DeliveryStatus) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET deliveryStatusRaw = ? WHERE id = ?",
                arguments: [status.rawString, messageId.uuidString]
            )
            guard db.changesCount > 0 else {
                throw MessageStoreError.messageNotFound(messageId)
            }
        }
    }

    // MARK: - Read

    func fetchMessages(for kind: MeshMessage.Kind, limit: Int = 200) async throws -> [MeshMessage] {
        let (kindType, kindValue): (String, String) = {
            switch kind {
            case .channel(let idx): return ("channel", String(idx))
            case .direct(let cid):  return ("direct", cid)
            }
        }()
        return try await dbQueue.read { db in
            let records = try MessageRecord
                .filter(Column("kindType") == kindType && Column("kindValue") == kindValue)
                .order(Column("timestamp").asc)
                .limit(limit)
                .fetchAll(db)
            return records.map { $0.toMeshMessage() }
        }
    }

    // MARK: - Backup / Restore

    var databaseURL: URL? {
        let path = dbQueue.path
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func exportBackup(to destination: URL) throws {
        guard databaseURL != nil else { return }
        let destQueue = try DatabaseQueue(path: destination.path)
        try dbQueue.backup(to: destQueue)
    }

    func importBackup(from source: URL) throws {
        guard let destURL = databaseURL else { return }
        // Validate backup contains expected schema
        let testQueue = try DatabaseQueue(path: source.path)
        guard try testQueue.read({ db in try db.tableExists("messages") }) else {
            throw MessageStoreError.invalidBackup
        }
        // Copy to temp file, then atomically replace destination
        let tmpURL = destURL.deletingLastPathComponent()
            .appendingPathComponent("messages_import_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try FileManager.default.copyItem(at: source, to: tmpURL)
        try FileManager.default.replaceItem(at: destURL, withItemAt: tmpURL,
                                            backupItemName: nil, options: [],
                                            resultingItemURL: nil)
    }
}

enum MessageStoreError: Error {
    case messageNotFound(UUID)
    case invalidBackup
}
