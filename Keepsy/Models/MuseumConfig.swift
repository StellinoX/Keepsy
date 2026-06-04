import Foundation

struct Museum: Identifiable {
    let id: String
    let name: String
    let packetImageName: String
}

struct MuseumConfig {
    static let shared = MuseumConfig()

    let museums: [Museum] = [
        Museum(id: "capodimonte", name: "Capodimonte", packetImageName: "capodimonte_pacchetto"),
        Museum(id: "uffizi", name: "Uffizi", packetImageName: "uffizi_pacchetto")
        // Museum(id: "louvre", name: "Louvre", packetImageName: "louvre_pacchetto")
    ]
}
