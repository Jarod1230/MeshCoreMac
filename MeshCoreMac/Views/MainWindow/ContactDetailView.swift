// MeshCoreMac/Views/MainWindow/ContactDetailView.swift
import SwiftUI

struct ContactDetailView: View {
    @State var contact: MeshContact
    let onSave: (MeshContact) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Identität") {
                LabeledContent("Node-ID", value: contact.id)
                LabeledContent("Name") {
                    TextField("Name", text: $contact.name)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Status") {
                LabeledContent("Online") {
                    HStack {
                        Circle()
                            .fill(contact.isOnline ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(contact.isOnline ? "Ja" : "Nein")
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastSeen = contact.lastSeen {
                    LabeledContent("Zuletzt gesehen",
                                   value: lastSeen.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if contact.lat != nil || contact.lon != nil {
                Section("Position") {
                    if let lat = contact.lat {
                        LabeledContent("Breite", value: String(format: "%.6f°", lat))
                    }
                    if let lon = contact.lon {
                        LabeledContent("Länge", value: String(format: "%.6f°", lon))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    onSave(contact)
                    dismiss()
                }
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }
}
