import Foundation

struct MeshContact: Identifiable, Hashable, Sendable {
    let id: String     // Hex-Node-Adresse aus MeshCore (z.B. "a1b2c3d4")
    var name: String
    var lastSeen: Date?
    var isOnline: Bool
    var lat: Double?
    var lon: Double?
}
