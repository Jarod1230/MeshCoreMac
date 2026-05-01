struct MeshChannel: Identifiable, Hashable, Sendable {
    let id: Int       // Kanal-Index (0-basiert, wie im MeshCore-Protokoll)
    let name: String
}
