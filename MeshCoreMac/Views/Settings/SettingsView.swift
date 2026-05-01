// MeshCoreMac/Views/Settings/SettingsView.swift
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let messageStore: MessageStore

    @State private var showExportPanel = false
    @State private var showImportPanel = false
    @State private var statusMessage: String? = nil

    var body: some View {
        Form {
            Section("Daten") {
                Button("Backup erstellen…") { showExportPanel = true }
                Button("Backup wiederherstellen…") { showImportPanel = true }
                    .foregroundStyle(.orange)
            }

            if let status = statusMessage {
                Section {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400)
        .fileExporter(
            isPresented: $showExportPanel,
            document: BackupDocument(store: messageStore),
            contentType: .meshcoreBackup,
            defaultFilename: "MeshCore-Backup-\(formattedDate)"
        ) { result in
            switch result {
            case .success: statusMessage = "Backup erfolgreich erstellt."
            case .failure(let err): statusMessage = "Backup fehlgeschlagen: \(err.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showImportPanel,
            allowedContentTypes: [.meshcoreBackup]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    try messageStore.importBackup(from: url)
                    statusMessage = "Backup erfolgreich wiederhergestellt."
                } catch {
                    statusMessage = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
                }
            case .failure(let err):
                statusMessage = "Fehler beim Öffnen: \(err.localizedDescription)"
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.meshcoreBackup] }
    let store: MessageStore

    init(store: MessageStore) { self.store = store }
    init(configuration: ReadConfiguration) throws {
        fatalError("Import wird über fileImporter gehandhabt")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("meshcorebackup")
        try store.exportBackup(to: tempURL)
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let meshcoreBackup = UTType(exportedAs: "de.Jarod1230.meshcoremac.backup")
}
