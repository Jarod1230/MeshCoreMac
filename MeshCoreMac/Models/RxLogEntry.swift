// MeshCoreMac/Models/RxLogEntry.swift
import Foundation

struct RxLogEntry: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case incoming = "↓"
        case outgoing = "↑"
    }

    let id: UUID
    let timestamp: Date
    let direction: Direction
    let rawBytes: Data
    let decoded: String?

    var hexString: String {
        rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var commandByte: UInt8? { rawBytes.first }
}
