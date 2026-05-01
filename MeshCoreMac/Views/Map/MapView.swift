// MeshCoreMac/Views/Map/MapView.swift
import CoreLocation
import MapKit
import SwiftUI

struct NodeMapView: View {
    let contacts: [MeshContact]
    let ownPosition: CLLocationCoordinate2D?

    private var nodesWithPosition: [MeshContact] {
        contacts.filter { $0.lat != nil && $0.lon != nil }
    }

    var body: some View {
        Group {
            if ownPosition == nil && nodesWithPosition.isEmpty {
                emptyState
            } else {
                mapContent
            }
        }
        .navigationTitle("Karte")
        .frame(minWidth: 500, minHeight: 400)
    }

    private var mapContent: some View {
        Map {
            if let pos = ownPosition {
                Annotation("Mein Node", coordinate: pos) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue, in: Circle())
                }
            }
            ForEach(nodesWithPosition) { contact in
                let coord = CLLocationCoordinate2D(
                    latitude: contact.lat!,
                    longitude: contact.lon!
                )
                Annotation(contact.name, coordinate: coord) {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            contact.isOnline ? Color.green : Color.gray,
                            in: Circle()
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Keine Positionen",
            systemImage: "map",
            description: Text("Warte auf GPS-Daten von Nodes in der Nähe.")
        )
    }
}
