import Foundation
import CloudKit

struct NetworkArtwork: Codable {
    let id: String
    let title: String
    let description: String?
    let artist: String?
    let imageUrl: String
    let createdAt: String
    let internalName: String
    
    // Original database split fields
    let inventoryNumber: String?
    let date: String?
    let technique: String?
    let dimensions: String?
}

class NetworkService {
    static let shared = NetworkService()
    
    private let publicDB = CKContainer(identifier: "iCloud.group.keepsy.app").publicCloudDatabase
    
    /// Fetches all artwork records matching the specified museum ID from Apple's CloudKit Public Database.
    func fetchArtworks(for museumId: String) async throws -> [NetworkArtwork] {
        let predicate = NSPredicate(format: "museumId == %@", museumId.lowercased())
        let query = CKQuery(recordType: "Artwork", predicate: predicate)
        
        return try await withCheckedThrowingContinuation { continuation in
            publicDB.fetch(withQuery: query, resultsLimit: 100) { result in
                switch result {
                case .success((let matchResults, _)):
                    var artworks: [NetworkArtwork] = []
                    
                    for (_, recordResult) in matchResults {
                        if case .success(let record) = recordResult {
                            let id = record.recordID.recordName
                            let title = record["title"] as? String ?? "Senza Titolo"
                            let artist = record["artist"] as? String
                            let description = record["description"] as? String
                            let internalName = record["internalName"] as? String ?? ""
                            let imageUrl = record["imageUrl"] as? String ?? ""
                            
                            let inventoryNumber = record["inventoryNumber"] as? String
                            let date = record["date"] as? String
                            let technique = record["technique"] as? String
                            let dimensions = record["dimensions"] as? String
                            
                            let artwork = NetworkArtwork(
                                id: id,
                                title: title,
                                description: description,
                                artist: artist,
                                imageUrl: imageUrl,
                                createdAt: Date().description,
                                internalName: internalName,
                                inventoryNumber: inventoryNumber,
                                date: date,
                                technique: technique,
                                dimensions: dimensions
                            )
                            artworks.append(artwork)
                        }
                    }
                    continuation.resume(returning: artworks)
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
