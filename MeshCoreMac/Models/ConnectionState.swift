enum ConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting(peripheralName: String)
    case connected(peripheralName: String)
    case ready(peripheralName: String)
    case failed(peripheralName: String, error: String)

    var displayName: String {
        switch self {
        case .disconnected:                    return "Getrennt"
        case .scanning:                        return "Suche Node…"
        case .connecting(let name):            return "Verbinde \(name)…"
        case .connected(let name):             return "Verbunden: \(name)"
        case .ready(let name):                 return "Bereit: \(name)"
        case .failed(_, let err):              return "Fehler: \(err)"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isConnectedOrReady: Bool {
        switch self {
        case .connected, .ready: return true
        case .disconnected, .scanning, .connecting, .failed: return false
        }
    }
}
