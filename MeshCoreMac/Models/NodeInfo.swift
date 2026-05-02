import Foundation

struct NodeInfo: Sendable, Equatable {
    let nodeId: String
    let firmwareVersion: Int
    let maxContacts: Int
    let maxChannels: Int
    let firmwareBuild: String
    let model: String
    let version: String
    let radioFrequencyHz: UInt32
    let radioBandwidthHz: UInt32
    let radioSpreadingFactor: UInt8
    let radioCodingRate: UInt8
}
