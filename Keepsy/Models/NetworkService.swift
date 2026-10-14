import Foundation
import FirebaseCore
import FirebaseFirestore

enum ArtworkSafetyPolicy {
    // Reviewed against App Store objectionable-content and age-rating guidance.
    // Keep this fallback list so blocked works remain unavailable when the device is offline.
    private static let blockedInternalNames: Set<String> = [
        "botticelli-the-birth-of-venus",
        "caravaggio-head-of-medusa",
        "caravaggio-the-sacrifice-of-isaac",
        "pollaiuolo-hercules-and-antaeus",
        "tiziano-flora",
        "tiziano-venus-of-urbino",
        "prado-bosch-triptych-of-garden-of-earthly-delights",
        "prado-bruegel-the-triumph-of-death",
        "prado-caravaggio-david-and-goliath",
        "prado-goya-y-lucientes-saturn-devouring-one-of-his-children",
        "prado-goya-y-lucientes-the-nude-and-clothed-maja",
        "prado-goya-y-lucientes-the-nude-maja-la-maja-desnuda",
        "prado-goya-y-lucientes-the-third-of-may-1808-the-execution-of",
        "prado-ribera-martyrdom-of-st-philip",
        "prado-rubens-nymphs-and-satyrs",
        "prado-tiziano-danae-with-a-nurse",
        "moma-gauguin-the-moon-and-the-earth",
        "moma-matisse-nude-with-blue-cushion-nu-au-coussin-bleu",
        "moma-picasso-boy-leading-a-horse"
    ]

    private static let localOverridesKey = "ArtworkSafetyLocalOverrides"

    static func allows(internalName: String, remoteApproval: Bool? = nil) -> Bool {
        if let override = localOverrides[internalName] {
            return override
        }
        if let remoteApproval {
            return remoteApproval
        }
        return !blockedInternalNames.contains(internalName)
    }

    static func isFallbackBlocked(_ internalName: String) -> Bool {
        blockedInternalNames.contains(internalName)
    }

    static func reviewReason(internalName: String, remoteApproval: Bool?) -> String {
        if localOverrides[internalName] != nil {
            return "Local review override"
        }
        if remoteApproval == false {
            return "Blocked in Firestore"
        }
        return blockedInternalNames.contains(internalName) ? "Reviewed safety block" : "Allowed"
    }

    static func setLocalOverride(_ isAllowed: Bool, for internalName: String) {
        var overrides = localOverrides
        overrides[internalName] = isAllowed
        UserDefaults.standard.set(overrides, forKey: localOverridesKey)
    }

    static func removeLocalOverride(for internalName: String) {
        var overrides = localOverrides
        overrides.removeValue(forKey: internalName)
        UserDefaults.standard.set(overrides, forKey: localOverridesKey)
    }

    static func clearLocalOverrides() {
        UserDefaults.standard.removeObject(forKey: localOverridesKey)
    }

    private static var localOverrides: [String: Bool] {
        UserDefaults.standard.dictionary(forKey: localOverridesKey) as? [String: Bool] ?? [:]
    }
}

struct NetworkArtwork: Codable, Identifiable {
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
    let isAppStoreAllowed: Bool?
}

class NetworkService {
    static let shared = NetworkService()

    private var db: Firestore? {
        if FirebaseApp.app() == nil {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                FirebaseApp.configure()
            }
        }
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }

    func fetchArtworks(for museumId: String, includeBlocked: Bool = false) async throws -> [NetworkArtwork] {
        guard let db else {
            return []
        }
        let snapshot = try await db.collection("artworks")
            .whereField("museumId", isEqualTo: museumId)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()

            let imageFilename = data["imageFilename"] as? String ?? ""
            let internalName = imageFilename.hasSuffix(".jpg")
                ? String(imageFilename.dropLast(4))
                : imageFilename
            let imageUrl = data["imageUrl"] as? String ?? ""

            // Required field check; skip malformed documents instead of inserting "Untitled".
            guard let title = data["title"] as? String else { return nil }
            let remoteApproval = data["isAppStoreAllowed"] as? Bool
            guard includeBlocked || ArtworkSafetyPolicy.allows(
                internalName: internalName,
                remoteApproval: remoteApproval
            ) else { return nil }

            return NetworkArtwork(
                id: doc.documentID,
                title: title,
                description: data["description"] as? String,
                artist: data["artist"] as? String,
                imageUrl: imageUrl,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue().ISO8601Format()
                    ?? Date().ISO8601Format(),
                internalName: internalName,
                inventoryNumber: data["inventoryNumber"] as? String,
                date: data["date"] as? String,
                technique: data["technique"] as? String,
                dimensions: data["dimensions"] as? String,
                museumId: museumId,
                cardNumber: data["cardNumber"] as? Int,
                isAppStoreAllowed: remoteApproval
            )
        }
    }

    /// Updates the approval/visibility of an artwork in Firestore and re-numbers all
    /// visible artworks in that museum to consecutive 1-based card numbers (1...N).
    func setArtworkAllowed(artworkId: String, museumId: String, isAllowed: Bool) async throws {
        try await resequenceMuseum(
            museumId: museumId,
            overrideArtworkId: artworkId,
            overrideIsAllowed: isAllowed
        )
        await CardDatabase.syncWithCloud(force: true)
        await MainActor.run {
            NotificationCenter.default.post(name: .artworkDatabaseUpdated, object: nil)
        }
    }

    /// Re-sequences card numbers (1...N) for all visible artworks in a museum in Firestore.
    func resequenceMuseum(
        museumId: String,
        overrideArtworkId: String? = nil,
        overrideIsAllowed: Bool? = nil
    ) async throws {
        let allInMuseum = try await fetchArtworks(for: museumId, includeBlocked: true)

        let resolvedArtworks: [(artwork: NetworkArtwork, isVisible: Bool)] = allInMuseum.map { art in
            let isVisible: Bool
            if art.id == overrideArtworkId, let override = overrideIsAllowed {
                isVisible = override
            } else if let remoteApproval = art.isAppStoreAllowed {
                isVisible = remoteApproval
            } else {
                isVisible = !ArtworkSafetyPolicy.isFallbackBlocked(art.internalName)
            }
            return (artwork: art, isVisible: isVisible)
        }

        let visibleArtworks = resolvedArtworks
            .filter { $0.isVisible }
            .map { $0.artwork }
            .sorted { a, b in
                let numA = a.cardNumber ?? Int.max
                let numB = b.cardNumber ?? Int.max
                if numA != numB { return numA < numB }
                if a.title != b.title { return a.title < b.title }
                return a.internalName < b.internalName
            }

        let hiddenArtworks = resolvedArtworks
            .filter { !$0.isVisible }
            .map { $0.artwork }

        guard let db else { return }
        let batch = db.batch()

        for (index, art) in visibleArtworks.enumerated() {
            let docRef = db.collection("artworks").document(art.id)
            let newNumber = index + 1 // 1-based: 1, 2, 3...
            batch.updateData([
                "isAppStoreAllowed": true,
                "cardNumber": newNumber
            ], forDocument: docRef)
        }

        for art in hiddenArtworks {
            let docRef = db.collection("artworks").document(art.id)
            batch.updateData([
                "isAppStoreAllowed": false,
                "cardNumber": FieldValue.delete()
            ], forDocument: docRef)
        }

        try await batch.commit()
    }

    /// Re-sequences card numbers for all museums in Firestore (1...N).
    func resequenceAllMuseums() async throws {
        for museum in MuseumConfig.shared.museums {
            try await resequenceMuseum(museumId: museum.id)
        }
        await CardDatabase.syncWithCloud(force: true)
        await MainActor.run {
            NotificationCenter.default.post(name: .artworkDatabaseUpdated, object: nil)
        }
    }
}
