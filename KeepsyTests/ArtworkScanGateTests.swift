import Foundation
import Testing
@testable import Keepsy

struct ArtworkScanGateTests {
    @Test func referenceVariantsUnlockOnlyOnce() {
        var gate = ArtworkScanGate(targetName: "painting")
        let selection = gate.selectionID
        let first = gate.accept(artworkName: "painting", selectionID: selection, time: 0)
        let repeated = gate.accept(artworkName: "painting", selectionID: selection, time: 5)
        #expect(first)
        #expect(!repeated)
    }

    @Test func cooldownCanRetryWithoutNeedingANewAnchor() {
        var gate = ArtworkScanGate(targetName: "first")
        let first = gate.accept(artworkName: "first", selectionID: gate.selectionID, time: 0)
        gate.select("second")
        let selection = gate.selectionID
        let duringAnimation = gate.accept(artworkName: "second", selectionID: selection, time: 2)
        let afterAnimation = gate.accept(artworkName: "second", selectionID: selection, time: 4)
        #expect(first)
        #expect(!duringAnimation)
        #expect(afterAnimation)
    }

    @Test func queuedDetectionCannotSurviveSelectionRoundTrip() {
        var gate = ArtworkScanGate(targetName: "first")
        let oldSelection = gate.selectionID
        gate.select("second")
        gate.select("first")
        let stale = gate.accept(artworkName: "first", selectionID: oldSelection, time: 0)
        let current = gate.accept(artworkName: "first", selectionID: gate.selectionID, time: 0)
        #expect(!stale)
        #expect(current)
    }

    @Test func interruptionInvalidatesQueuedDetectionsWithoutConsumingTheCard() {
        var gate = ArtworkScanGate(targetName: "painting")
        let oldSelection = gate.selectionID
        gate.invalidatePendingDetections()
        let stale = gate.accept(artworkName: "painting", selectionID: oldSelection, time: 0)
        let current = gate.accept(artworkName: "painting", selectionID: gate.selectionID, time: 0)
        #expect(!stale)
        #expect(current)
    }

    @Test func wrongArtworkDoesNotConsumeTheCooldown() {
        var gate = ArtworkScanGate(targetName: "painting")
        let wrong = gate.accept(artworkName: "different", selectionID: gate.selectionID, time: 0)
        let correct = gate.accept(artworkName: "painting", selectionID: gate.selectionID, time: 0)
        #expect(!wrong)
        #expect(correct)
    }

    @Test func repeatedViewUpdatesKeepTheSelectionValid() {
        var gate = ArtworkScanGate(targetName: "painting")
        let selection = gate.selectionID
        gate.select("painting")
        let accepted = gate.accept(artworkName: "painting", selectionID: selection, time: 0)
        #expect(accepted)
    }

    @Test func scanningRequiresTheCurrentSelection() {
        var gate = ArtworkScanGate(targetName: "")
        let unselected = gate.accept(artworkName: "puppies", selectionID: gate.selectionID, time: 0)
        #expect(!unselected)

        gate.select("lily")
        let unfocused = gate.accept(artworkName: "puppies", selectionID: gate.selectionID, time: 1)
        #expect(!unfocused)

        gate.select("puppies")
        let focused = gate.accept(artworkName: "puppies", selectionID: gate.selectionID, time: 2)
        #expect(focused)
    }
}
