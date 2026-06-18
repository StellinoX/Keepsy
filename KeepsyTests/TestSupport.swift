import Foundation
@testable import Keepsy

/// Shared helpers for resetting the global `UserDefaults` + in-memory caches that
/// `CardDatabase` reads/writes. Every state test starts from a clean slate so tests
/// stay order-independent even though they touch process-wide singletons.
enum TestSupport {
    /// A museum id that does not collide with real museums in `MuseumConfig`.
    static let testCity = "testmuseum"

    /// All UserDefaults keys CardDatabase touches, per-city and legacy.
    static func resetState(city: String = testCity) {
        let d = UserDefaults.standard
        let keys = [
            "FoundCards", "RevealedCards", "DuplicateCardCounts",
            "currentCity",
            "CachedRemoteArtworks", "CachedMuseumMap",
            "activePackCards", "activePackTearMask", "activePackDuplicates",
            "activePackCards_\(city)", "activePackTearMask_\(city)", "activePackDuplicates_\(city)",
        ]
        for key in keys { d.removeObject(forKey: key) }

        // Reset in-memory static caches too (backed by dictLock).
        CardDatabase.remoteArtworks = [:]
        CardDatabase.artworksByMuseum = [:]
        CardDatabase.imageCache.removeAllObjects()
    }

    /// Builds a `NetworkArtwork` with sensible defaults; override only what a test cares about.
    static func artwork(
        internalName: String,
        title: String = "Untitled",
        museumId: String? = nil,
        imageUrl: String = "",
        dimensions: String? = nil
    ) -> NetworkArtwork {
        NetworkArtwork(
            id: internalName,
            title: title,
            description: nil,
            artist: nil,
            imageUrl: imageUrl,
            createdAt: "2026-01-01",
            internalName: internalName,
            inventoryNumber: nil,
            date: nil,
            technique: nil,
            dimensions: dimensions,
            museumId: museumId
        )
    }
}
