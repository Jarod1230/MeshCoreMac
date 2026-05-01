import Foundation

struct MeshMessage: Identifiable, Equatable, Sendable {
    let id: UUID

    enum Kind: Equatable, Sendable {
        case channel(index: Int)
        case direct(contactId: String)
    }

    struct Routing: Equatable, Sendable {
        var hops: Int
        var snr: Float       // dB, z.B. -8.5
        var routeDisplay: String?  // z.B. "via R-7"
    }

    enum DeliveryStatus: Equatable, Sendable {
        case sending
        case sent
        case delivered
        case failed(String)
    }

    let kind: Kind
    let senderName: String
    let text: String
    let timestamp: Date
    var routing: Routing?
    var deliveryStatus: DeliveryStatus
    var isIncoming: Bool
}
