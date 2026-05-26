import Foundation

struct NetworkArtwork: Codable {
    let id: String
    let title: String
    let description: String?
    let artist: String?
    let imageUrl: String
    let createdAt: String
    
    var internalName: String {
        guard let url = URL(string: imageUrl) else { return title }
        let filename = url.lastPathComponent
        return filename.replacingOccurrences(of: ".jpg", with: "").replacingOccurrences(of: ".png", with: "")
    }
}

Task {
    do {
        let url = URL(string: "https://keepsy-api.onrender.com/api/artworks")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let artworks = try JSONDecoder().decode([NetworkArtwork].self, from: data)
        print("Success! Decoded \(artworks.count) artworks.")
        if let first = artworks.first {
            print("First artwork title: \(first.title)")
            print("Internal name: \(first.internalName)")
        }
    } catch {
        print("Error decoding: \(error)")
    }
    exit(0)
}

RunLoop.main.run()
