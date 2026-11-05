import Foundation
import Testing
@testable import Keepsy

struct ArtworkScanHoldTests {
    @Test func briefAccidentalFramingDoesNotCapture() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        let partial = observeThrough(1.5, hold: &hold)
        let lost = hold.observe(visibleNames: [], time: 1.6)
        #expect(partial.fraction == 0.75)
        #expect(!partial.isComplete)
        #expect(lost == .idle)
    }

    @Test func twoContinuousSecondsCompleteTheHold() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        let beforeCompletion = observeThrough(1.9, hold: &hold)
        let completed = hold.observe(visibleNames: ["painting"], time: 2)
        #expect(!beforeCompletion.isComplete)
        #expect(completed.isComplete)
        #expect(completed.artworkName == "painting")
    }

    @Test func leavingAndReturningStartsFromZero() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        _ = observeThrough(1.8, hold: &hold)
        _ = hold.observe(visibleNames: [], time: 1.9)
        let restarted = hold.observe(visibleNames: ["painting"], time: 2)
        let nextFrame = hold.observe(visibleNames: ["painting"], time: 2.1)
        #expect(restarted.fraction == 0)
        #expect(nextFrame.fraction < 0.1)
        #expect(!nextFrame.isComplete)
    }

    @Test func cameraFrameGapCannotCompleteAnOldHold() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        _ = observeThrough(1.8, hold: &hold)
        let resumed = hold.observe(visibleNames: ["painting"], time: 3)
        #expect(resumed.fraction == 0)
        #expect(!resumed.isComplete)
    }

    @Test func changingArtworkDoesNotTransferProgress() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        _ = observeThrough(1.8, hold: &hold)
        let changed = hold.observe(visibleNames: ["other"], time: 1.9)
        #expect(changed.artworkName == "other")
        #expect(changed.fraction == 0)
    }

    @Test func interruptionOrSelectionResetRequiresAFullNewHold() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        _ = observeThrough(1.8, hold: &hold)
        hold.reset()
        let resumed = hold.observe(visibleNames: ["painting"], time: 1.9)
        #expect(resumed.fraction == 0)
        #expect(!resumed.isComplete)
    }

    @Test func referenceVariantChangesKeepTheSameArtworkHold() {
        // Both reference variants yield the same card name, regardless of anchor ID.
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        let halfway = observeThrough(1, hold: &hold)
        let completed = observeThrough(2, from: 11, hold: &hold)
        #expect(halfway.fraction == 0.5)
        #expect(completed.isComplete)
    }

    @Test func repeatedOrOutOfOrderFramesCannotAdvanceProgress() {
        var hold = ArtworkScanHold()
        _ = hold.observe(visibleNames: ["painting"], time: 0)
        let halfway = observeThrough(1, hold: &hold)
        let stale = hold.observe(visibleNames: ["painting"], time: 0.5)
        let repeated = hold.observe(visibleNames: ["painting"], time: 1)
        #expect(stale == halfway)
        #expect(repeated == halfway)
    }

    private func observeThrough(_ end: Double, from firstStep: Int = 1,
                                hold: inout ArtworkScanHold) -> ArtworkScanHold.Progress {
        var result = hold.progress
        for step in firstStep...Int((end * 10).rounded()) {
            result = hold.observe(visibleNames: ["painting"], time: Double(step) / 10)
        }
        return result
    }
}
