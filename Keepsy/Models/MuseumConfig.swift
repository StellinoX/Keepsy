import Foundation

struct Museum: Identifiable {
    let id: String
    let name: String
    let city: String          // ← aggiungi questa riga
    let packetImageName: String
    let latitude: Double
    let longitude: Double
    let geofenceRadius: Double
}

struct CarouselPack: Identifiable {
    let id: String
    let name: String
    let packetImageName: String
}

struct MuseumConfig {
    static let shared = MuseumConfig()
    static let fareImpresa = CarouselPack(
        id: "fare-impresa", name: "fare impresa", packetImageName: "fare_impresa_pacchetto"
    )

    let museums: [Museum] = [
        Museum(id: "uffizi",      name: "Uffizi",      city: "Florence, Italy", packetImageName: "uffizi_pacchetto",      latitude: 43.7677, longitude: 11.2556,  geofenceRadius: 500.0),
        Museum(id: "prado",       name: "Prado",       city: "Madrid, Spain",   packetImageName: "prado_pacchetto",       latitude: 40.4138, longitude: -3.6921,  geofenceRadius: 500.0),
        Museum(id: "moma",        name: "MoMA",        city: "New York, USA",   packetImageName: "moma_pacchetto",        latitude: 40.7614, longitude: -73.9776, geofenceRadius: 500.0),
    ]

    func packetImageName(for id: String) -> String? {
        if id == Self.fareImpresa.id { return Self.fareImpresa.packetImageName }
        return museums.first(where: { $0.id == id })?.packetImageName
    }

    var artworkCatalogIDs: [String] {
        museums.map(\.id) + [Self.fareImpresa.id]
    }
}
