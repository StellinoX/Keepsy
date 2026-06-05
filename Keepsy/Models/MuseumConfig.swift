import Foundation

struct Museum: Identifiable {
    let id: String
    let name: String
    let packetImageName: String
    let latitude: Double
    let longitude: Double
    let geofenceRadius: Double // in meters
}

struct MuseumConfig {
    static let shared = MuseumConfig()

    let museums: [Museum] = [
        Museum(id: "capodimonte", name: "Capodimonte", packetImageName: "capodimonte_pacchetto", latitude: 40.8672, longitude: 14.2505, geofenceRadius: 500.0),
        Museum(id: "uffizi",      name: "Uffizi",      packetImageName: "uffizi_pacchetto",      latitude: 43.7677, longitude: 11.2556, geofenceRadius: 500.0),
        Museum(id: "prado",       name: "Prado",       packetImageName: "prado_pacchetto",       latitude: 40.4138, longitude: -3.6921, geofenceRadius: 500.0),
        Museum(id: "moma",        name: "MoMA",        packetImageName: "moma_pacchetto",        latitude: 40.7614, longitude: -73.9776, geofenceRadius: 500.0),
    ]
}
