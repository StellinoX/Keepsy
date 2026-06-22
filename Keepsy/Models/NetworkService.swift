import Foundation
import FirebaseFirestore

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
    let museumId: String?
    let cardNumber: Int?
}

class NetworkService {
    static let shared = NetworkService()

    private let db = Firestore.firestore()

    private var artworksDirectory: URL {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artworks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docDir.path) {
            try? FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        }
        return docDir
    }

    func fetchArtworks(for museumId: String) async throws -> [NetworkArtwork] {
        let snapshot = try await db.collection("artworks")
            .whereField("museumId", isEqualTo: museumId)
            .getDocuments()

        var artworks: [NetworkArtwork] = []
        var pendingDownloads: [(url: String, name: String)] = []

        for doc in snapshot.documents {
            let data = doc.data()

            let imageFilename = data["imageFilename"] as? String ?? ""
            let internalName = imageFilename.hasSuffix(".jpg")
                ? String(imageFilename.dropLast(4))
                : imageFilename
            let imageUrl = data["imageUrl"] as? String ?? ""

            artworks.append(NetworkArtwork(
                id: doc.documentID,
                title: data["title"] as? String ?? "Untitled",
                description: data["description"] as? String,
                artist: data["artist"] as? String,
                imageUrl: imageUrl,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue().description ?? Date().description,
                internalName: internalName,
                inventoryNumber: data["inventoryNumber"] as? String,
                date: data["date"] as? String,
                technique: data["technique"] as? String,
                dimensions: data["dimensions"] as? String,
                museumId: museumId,
                cardNumber: data["cardNumber"] as? Int
            ))

            if !imageUrl.isEmpty && !internalName.isEmpty {
                pendingDownloads.append((url: imageUrl, name: internalName))
            }
        }

        return artworks
    }

    private func downloadImageIfNeeded(from urlString: String, name: String) async {
        let destinationURL = artworksDirectory.appendingPathComponent("\(name).jpg")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int) ?? 0
            if size > 10000 { return }
        }

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: destinationURL, options: .atomic)
            // SwiftUI's .onReceive asserts main queue — post on main thread.
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .artworkImageDownloaded,
                    object: nil,
                    userInfo: ["internalName": name]
                )
            }
        } catch {
            print("❌ Download failed for \(name): \(error.localizedDescription)")
        }
    }
}
