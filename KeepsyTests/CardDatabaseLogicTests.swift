import Testing
import Foundation
@testable import Keepsy

/// Tests for the pure-ish derivation logic in `CardDatabase`: name cleaning,
/// museum→artwork resolution, disk filtering, and deterministic styling.
@Suite(.serialized)
@MainActor
struct CardDatabaseLogicTests {
    let city = TestSupport.testCity

    init() { TestSupport.resetState() }

    // MARK: - cleanedArtworkName (fallback cleaning branch, name absent from DB)

    @Test func cleanedNameSpecialCaseVale() {
        #expect(CardDatabase.cleanedArtworkName("vale") == "Vale")
    }

    @Test func cleanedNameStripsNumericPrefixAndPhSuffix() {
        let raw = "1 - Q 36 Masaccio_Crocifissione_ph.L.Romano_0779"
        #expect(CardDatabase.cleanedArtworkName(raw) == "Q 36 Masaccio Crocifissione")
    }

    @Test func cleanedNameReplacesUnderscores() {
        #expect(CardDatabase.cleanedArtworkName("Some_Long_Name") == "Some Long Name")
    }

    @Test func cleanedNameRemovesDetailMarker() {
        #expect(CardDatabase.cleanedArtworkName("Foo_detail_Bar") == "FooBar")
    }

    // MARK: - cleanedArtworkName (DB title branch)

    @Test func cleanedNamePrefersDatabaseTitle() {
        CardDatabase.remoteArtworks = ["k": TestSupport.artwork(internalName: "k", title: "Official Title")]
        #expect(CardDatabase.cleanedArtworkName("k") == "Official Title")
    }

    // MARK: - artworksFor

    @Test func artworksForUsesMuseumMapFirst() {
        CardDatabase.artworksByMuseum = [city: ["a", "b"]]
        #expect(CardDatabase.artworksFor(location: city) == ["a", "b"])
    }

    @Test func artworksForLowercasesLocation() {
        CardDatabase.artworksByMuseum = [city: ["a"]]
        #expect(CardDatabase.artworksFor(location: city.uppercased()) == ["a"])
    }

    @Test func artworksForFallsBackToStaticMap() {
        // No live map, no remote artworks → uses the bundled fallbackMuseumMap.
        let uffizi = CardDatabase.artworksFor(location: "uffizi")
        #expect(uffizi.count == 50)
        #expect(uffizi.contains("botticelli-primavera"))
    }

    @Test func artworksForDerivesFromRemoteByMuseumId() {
        CardDatabase.remoteArtworks = [
            "z2": TestSupport.artwork(internalName: "z2", museumId: "zoo"),
            "z1": TestSupport.artwork(internalName: "z1", museumId: "zoo"),
            "other": TestSupport.artwork(internalName: "other", museumId: "elsewhere"),
        ]
        // Returned sorted, filtered to the matching museumId.
        #expect(CardDatabase.artworksFor(location: "zoo") == ["z1", "z2"])
    }

    // MARK: - Card numbering & indexing

    @Test func cardNumberAndIndexForArtwork() {
        CardDatabase.remoteArtworks = [
            "art1": TestSupport.artwork(internalName: "art1", museumId: city, cardNumber: 1),
            "art2": TestSupport.artwork(internalName: "art2", museumId: city, cardNumber: 2),
        ]
        CardDatabase.artworksByMuseum = [city: ["art1", "art2"]]

        #expect(CardDatabase.cardNumber(for: "art1") == 1)
        #expect(CardDatabase.cardNumber(for: "art2") == 2)
        #expect(CardDatabase.cardIndex(for: "art1") == 0)
        #expect(CardDatabase.cardIndex(for: "art2") == 1)
    }

    @Test func hiddenCardsExcludedFromArtworksFor() {
        CardDatabase.remoteArtworks = [
            "visible": TestSupport.artwork(internalName: "visible", museumId: city, cardNumber: 1, isAppStoreAllowed: true),
            "hidden": TestSupport.artwork(internalName: "hidden", museumId: city, cardNumber: nil, isAppStoreAllowed: false),
        ]
        CardDatabase.artworksByMuseum = [city: ["visible", "hidden"]]

        let visibleList = CardDatabase.artworksFor(location: city)
        #expect(visibleList.contains("visible"))
        #expect(!visibleList.contains("hidden"))
    }

    // MARK: - downloadedArtworkNames

    @Test func downloadedArtworkNamesEmptyWhenNoFilesOnDisk() {
        CardDatabase.artworksByMuseum = [city: ["nofile1", "nofile2"]]
        #expect(CardDatabase.downloadedArtworkNames(for: city).isEmpty)
    }

    // MARK: - Deterministic styling

    @Test func colorsForIsDeterministicAndReturnsPair() {
        let colors = CardDatabase.colorsFor(name: "Mona Lisa")
        #expect(colors.count == 2)
        // Same name → same colors within a run (stable card appearance).
        #expect(CardDatabase.colorsFor(name: "Mona Lisa") == colors)
    }

    @Test func allArtworkNamesSorted() {
        CardDatabase.remoteArtworks = [
            "b": TestSupport.artwork(internalName: "b"),
            "a": TestSupport.artwork(internalName: "a"),
        ]
        #expect(CardDatabase.allArtworkNames == ["a", "b"])
    }
}
