import Foundation

struct Museum: Identifiable {
    let id: String
    let name: String
}

struct MuseumConfig {
    static let shared = MuseumConfig()
    
    let museums: [Museum] = [
        Museum(id: "capodimonte", name: "Capodimonte")
        // In the future, you can easily add the Louvre or other museums here:
        // Museum(id: "louvre", name: "Louvre")
    ]
}
