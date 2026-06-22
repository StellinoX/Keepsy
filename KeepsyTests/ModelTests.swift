import Testing
import Foundation
import SwiftUI
@testable import Keepsy

/// Codable round-trip + value-type model tests that don't touch global state.
@Suite
@MainActor
struct ModelTests {

    @Test func networkArtworkCodableRoundTrip() throws {
        let original = NetworkArtwork(
            id: "doc1",
            title: "Danae",
            description: "A painting",
            artist: "Tiziano",
            imageUrl: "https://example.com/danae.jpg",
            createdAt: "2026-01-01",
            internalName: "11 - Tiziano Vecellio_Danae",
            inventoryNumber: "Q123",
            date: "1544",
            technique: "Oil on canvas",
            dimensions: "120x170 cm",
            museumId: "capodimonte",
            cardNumber: 10
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkArtwork.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.internalName == original.internalName)
        #expect(decoded.imageUrl == original.imageUrl)
        #expect(decoded.museumId == original.museumId)
        #expect(decoded.dimensions == original.dimensions)
        #expect(decoded.cardNumber == original.cardNumber)
    }

    @Test func artworkCardEqualityIsByIdentity() {
        let g = CardDatabase.gradientFor(name: "x")
        let a = ArtworkCard(name: "x", imageName: "x", gradient: g)
        let b = ArtworkCard(name: "x", imageName: "x", gradient: g)
        // Distinct UUIDs → not equal, even with identical fields.
        #expect(a != b)
        #expect(a == a)
    }

    @Test func museumConfigHasUniqueIds() {
        let ids = MuseumConfig.shared.museums.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("capodimonte"))
    }
}
