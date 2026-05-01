// MeshCoreMac/Services/MessageStoreRecord.swift
import GRDB
import Foundation

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    var id: String
    var kindType: String     // "channel" | "direct"
    var kindValue: String    // channelIndex als String | contactId
    var senderName: String
    var text: String
    var timestamp: Date
    var hops: Int?
    var snr: Double?
    var routeDisplay: String?
    var deliveryStatusRaw: String
    var isIncoming: Bool

    init(from msg: MeshMessage) {
        self.id = msg.id.uuidString
        switch msg.kind {
        case .channel(let idx):
            self.kindType = "channel"; self.kindValue = String(idx)
        case .direct(let cid):
            self.kindType = "direct"; self.kindValue = cid
        }
        self.senderName = msg.senderName
        self.text = msg.text
        self.timestamp = msg.timestamp
        self.hops = msg.routing.map { $0.hops }
        self.snr = msg.routing.map { Double($0.snr) }
        self.routeDisplay = msg.routing?.routeDisplay
        self.deliveryStatusRaw = msg.deliveryStatus.rawString
        self.isIncoming = msg.isIncoming
    }

    func toMeshMessage() -> MeshMessage {
        let kind: MeshMessage.Kind = kindType == "channel"
            ? .channel(index: Int(kindValue) ?? 0)
            : .direct(contactId: kindValue)
        let routing: MeshMessage.Routing? = hops.map {
            MeshMessage.Routing(hops: $0, snr: Float(snr ?? 0), routeDisplay: routeDisplay)
        }
        return MeshMessage(
            id: UUID(uuidString: id) ?? UUID(),
            kind: kind,
            senderName: senderName,
            text: text,
            timestamp: timestamp,
            routing: routing,
            deliveryStatus: MeshMessage.DeliveryStatus(rawString: deliveryStatusRaw),
            isIncoming: isIncoming
        )
    }
}

extension MeshMessage.DeliveryStatus {
    var rawString: String {
        switch self {
        case .sending:          return "sending"
        case .sent:             return "sent"
        case .delivered:        return "delivered"
        case .failed(let msg):  return "failed:\(msg)"
        }
    }

    init(rawString: String) {
        if rawString.hasPrefix("failed:") {
            self = .failed(String(rawString.dropFirst(7)))
        } else {
            switch rawString {
            case "sending":   self = .sending
            case "sent":      self = .sent
            case "delivered": self = .delivered
            default:          self = .failed("Unbekannter Status")
            }
        }
    }
}
