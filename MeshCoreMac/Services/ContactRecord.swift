import GRDB
import Foundation

struct ContactRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "contacts"

    var id: String
    var name: String
    var lastSeen: Double?   // Date.timeIntervalSince1970
    var isOnline: Bool
    var lat: Double?
    var lon: Double?

    init(from contact: MeshContact) {
        id = contact.id
        name = contact.name
        lastSeen = contact.lastSeen?.timeIntervalSince1970
        isOnline = contact.isOnline
        lat = contact.lat
        lon = contact.lon
    }

    func toMeshContact() -> MeshContact {
        MeshContact(
            id: id,
            name: name,
            lastSeen: lastSeen.map { Date(timeIntervalSince1970: $0) },
            isOnline: isOnline,
            lat: lat,
            lon: lon
        )
    }
}
