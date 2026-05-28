import Foundation

struct NetworkArtwork: Codable {
    let id: String
    let title: String
    let description: String?
    let artist: String?
    let imageUrl: String
    let createdAt: String
    
    // We can compute the original "name" identifier (with underscores) from the imageUrl
    // since the server saves them as https://.../Vision_of_St_Bruno.jpg
    var internalName: String {
        guard let url = URL(string: imageUrl) else { return title }
        let filename = url.lastPathComponent
        return filename.replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
    }
}

class NetworkService {
    static let shared = NetworkService()
    func fetchArtworks(for museumId: String) async throws -> [NetworkArtwork] {
        guard let url = MuseumConfig.shared.url(for: museumId) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let artworks = try JSONDecoder().decode([NetworkArtwork].self, from: data)
        return artworks
    }
}
