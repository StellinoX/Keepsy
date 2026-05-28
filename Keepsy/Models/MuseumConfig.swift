import Foundation

struct Museum: Identifiable {
    let id: String
    let name: String
    let databaseUrl: String
}

struct MuseumConfig {
    static let shared = MuseumConfig()
    
    let museums: [Museum] = [
        Museum(id: "capodimonte", 
               name: "Capodimonte", 
               databaseUrl: "https://keepsy-art-images-rstudio.s3.us-east-2.amazonaws.com/database.json")
        // In the future, you can easily add the Louvre or other museums here:
        // Museum(id: "louvre", name: "Louvre", databaseUrl: "https://.../louvre.json")
    ]
    
    func url(for museumId: String) -> URL? {
        if let museum = museums.first(where: { $0.id == museumId }) {
            return URL(string: museum.databaseUrl)
        }
        return nil
    }
}
