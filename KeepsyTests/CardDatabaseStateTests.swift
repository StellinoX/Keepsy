import Testing
import Foundation
@testable import Keepsy

/// Tests for the UserDefaults-backed game state in `CardDatabase`: found/revealed cards,
/// duplicate tracking, and active-pack lifecycle. Serialized because the suite mutates
/// process-wide `UserDefaults` and static caches.
@Suite(.serialized)
@MainActor
struct CardDatabaseStateTests {
    let city = TestSupport.testCity

    init() { TestSupport.resetState() }

    // MARK: - Found / Revealed

    @Test func addFoundCardsStoresAndDedupes() {
        CardDatabase.addFoundCards(["a", "b", "a"])
        #expect(CardDatabase.getFoundCards() == ["a", "b"])

        CardDatabase.addFoundCards(["b", "c"])
        #expect(CardDatabase.getFoundCards() == ["a", "b", "c"])
    }

    @Test func getFoundCardsEmptyByDefault() {
        #expect(CardDatabase.getFoundCards().isEmpty)
        #expect(CardDatabase.getRevealedCards().isEmpty)
    }

    @Test func addRevealedCardAlsoMarksFound() {
        CardDatabase.addRevealedCard("x")
        #expect(CardDatabase.getRevealedCards().contains("x"))
        // Critical invariant: a revealed card must also be a found card.
        #expect(CardDatabase.getFoundCards().contains("x"))
    }

    // MARK: - Duplicate tracking

    @Test func trackDuplicatesCountsOnlyOwnedCards() {
        CardDatabase.addFoundCards(["owned"])

        let owned = CardDatabase.trackDuplicates(in: ["owned", "new"])
        #expect(owned == ["owned"])
        #expect(CardDatabase.getDuplicateCounts()["owned"] == 1)
        // A brand-new card is not a duplicate and must not be counted.
        #expect(CardDatabase.getDuplicateCounts()["new"] == nil)
    }

    @Test func trackDuplicatesIncrementsAcrossOpens() {
        CardDatabase.addFoundCards(["owned"])
        _ = CardDatabase.trackDuplicates(in: ["owned"])
        _ = CardDatabase.trackDuplicates(in: ["owned"])
        #expect(CardDatabase.getDuplicateCounts()["owned"] == 2)
    }

    @Test func trackDuplicatesEmptyWhenNothingOwned() {
        let owned = CardDatabase.trackDuplicates(in: ["fresh1", "fresh2"])
        #expect(owned.isEmpty)
        #expect(CardDatabase.getDuplicateCounts().isEmpty)
    }

    @Test func revealedCardCountsAsOwnedDuplicate() {
        CardDatabase.addRevealedCard("r")
        #expect(CardDatabase.trackDuplicates(in: ["r"]) == ["r"])
    }

    // MARK: - Active pack accessors

    @Test func getActivePackNilWhenNone() {
        #expect(CardDatabase.getActivePack(for: city) == nil)
        #expect(CardDatabase.hasActivePack(for: city) == false)
    }

    @Test func getActivePackReturnsStoredCards() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        #expect(CardDatabase.getActivePack(for: city) == ["a", "b"])
        #expect(CardDatabase.hasActivePack(for: city) == true)
    }

    @Test func getActivePackFallsBackToLegacyKey() {
        UserDefaults.standard.set(["legacy"], forKey: "activePackCards")
        #expect(CardDatabase.getActivePack(for: city) == ["legacy"])
    }

    // MARK: - Duplicates in active pack

    @Test func duplicatesInActivePackEmptyWithoutPack() {
        // Even with the duplicates key set, no active pack means no duplicates surface.
        UserDefaults.standard.set(["a"], forKey: "activePackDuplicates_\(city)")
        #expect(CardDatabase.getDuplicatesInActivePack(for: city).isEmpty)
    }

    @Test func duplicatesInActivePackReadsSavedList() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        UserDefaults.standard.set(["a"], forKey: "activePackDuplicates_\(city)")
        #expect(CardDatabase.getDuplicatesInActivePack(for: city) == ["a"])
    }

    // MARK: - isActivePackAllDuplicates

    @Test func allDuplicatesTrueWhenEveryCardRevealedOrDuplicate() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        CardDatabase.addRevealedCard("a")
        UserDefaults.standard.set(["b"], forKey: "activePackDuplicates_\(city)")
        #expect(CardDatabase.isActivePackAllDuplicates(for: city) == true)
    }

    @Test func allDuplicatesFalseWhenSomeCardStillSealed() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        CardDatabase.addRevealedCard("a")
        #expect(CardDatabase.isActivePackAllDuplicates(for: city) == false)
    }

    @Test func allDuplicatesFalseWhenNoPack() {
        #expect(CardDatabase.isActivePackAllDuplicates(for: city) == false)
    }

    // MARK: - clearActivePackIfNeeded

    @Test func clearActivePackClearsWhenFullyResolved() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        UserDefaults.standard.set("mask", forKey: "activePackTearMask_\(city)")
        CardDatabase.addRevealedCard("a")
        UserDefaults.standard.set(["b"], forKey: "activePackDuplicates_\(city)")

        CardDatabase.clearActivePackIfNeeded(for: city)

        #expect(CardDatabase.getActivePack(for: city) == nil)
        #expect(UserDefaults.standard.string(forKey: "activePackTearMask_\(city)") == nil)
        #expect(UserDefaults.standard.stringArray(forKey: "activePackDuplicates_\(city)") == nil)
    }

    @Test func clearActivePackKeepsWhenPartiallyResolved() {
        UserDefaults.standard.set(["a", "b"], forKey: "activePackCards_\(city)")
        CardDatabase.addRevealedCard("a") // b still sealed

        CardDatabase.clearActivePackIfNeeded(for: city)

        #expect(CardDatabase.getActivePack(for: city) == ["a", "b"])
    }
}
