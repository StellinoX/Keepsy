import Foundation
import Testing
@testable import Keepsy

@Suite
@MainActor
struct PackCarouselMotionTests {
    @Test func interruptedSettleStartsAtTheVisiblePosition() {
        var motion = PackCarouselMotion()
        motion.beginDrag()
        motion.endDrag(translation: -60, velocity: -900)
        motion.advance(seconds: 1.0 / 60, slotCount: 6)
        let visiblePosition = motion.position
        #expect(visiblePosition > 0 && visiblePosition < 1)

        motion.beginDrag()
        #expect(motion.position == visiblePosition)
        motion.drag(translation: -19)
        #expect(abs(motion.position - visiblePosition - 0.1) < 0.000001)
        motion.endDrag(translation: -60, velocity: -900)
        #expect(motion.target == 2)
    }

    @Test func actualTranslationDeterminesDirection() {
        var motion = PackCarouselMotion()
        motion.beginDrag()
        motion.endDrag(translation: -70, velocity: 2000)
        #expect(motion.target == 1)

        motion.beginDrag()
        motion.endDrag(translation: 70, velocity: -2000)
        #expect(motion.target == 0)
    }

    @Test func smallFlicksCanAdvanceButPredictionCannotReverseThem() {
        var motion = PackCarouselMotion()
        motion.beginDrag()
        motion.endDrag(translation: -12, velocity: -1500)
        #expect(motion.target == 1)

        motion.reset(to: 0)
        motion.beginDrag()
        motion.endDrag(translation: -12, velocity: 1500)
        #expect(motion.target == 0)
    }

    @Test func outgoingPackKeepsItsSideUntilInvisible() {
        let start = PackCarouselMotion.distance(slot: 5, position: 0, slotCount: 6)
        let during = PackCarouselMotion.distance(slot: 5, position: 0.75, slotCount: 6)
        #expect(start == -1)
        #expect(during == -1.75)
        // The wrap happens at ±3, beyond the fully transparent ±2 edge.
        let beforeWrap = PackCarouselMotion.distance(slot: 5, position: 1.99, slotCount: 6)
        let afterWrap = PackCarouselMotion.distance(slot: 5, position: 2.01, slotCount: 6)
        #expect(abs(beforeWrap) > 2 && abs(afterWrap) > 2)
    }

    @Test func thousandsOfInterruptedSwipesKeepTheRingPopulated() {
        var motion = PackCarouselMotion()
        for step in 0..<5000 {
            let direction: CGFloat = step % 7 == 0 ? 1 : -1
            motion.beginDrag()
            motion.endDrag(translation: direction * 80, velocity: direction * 1200)
            motion.advance(seconds: step % 3 == 0 ? 1.0 / 30 : 1.0 / 60, slotCount: 6)
            let distances = (0..<6).map {
                PackCarouselMotion.distance(slot: $0, position: motion.position, slotCount: 6)
            }
            #expect(distances.filter { abs($0) < 2 }.count >= 3)
            #expect(distances.contains { abs($0) <= 0.5 })
        }
        for _ in 0..<120 { motion.advance(seconds: 1.0 / 60, slotCount: 6) }
        #expect(!motion.isSettling)
        #expect(motion.position == CGFloat(motion.target))
        #expect((0..<6).contains(motion.target))
    }

    @Test func externalSelectionDoesNotRestartTheSwipeSettle() {
        var motion = PackCarouselMotion()
        motion.beginDrag()
        motion.endDrag(translation: -80, velocity: -1000)
        motion.advance(seconds: 1.0 / 60, slotCount: 6)
        let visiblePosition = motion.position
        motion.select(index: 1, museumCount: 3)
        #expect(motion.position == visiblePosition)
        #expect(motion.target == 1)
        motion.select(index: 2, museumCount: 3)
        #expect(motion.position == visiblePosition)
        #expect(motion.target == 2)
    }

    @Test func cancelledDragReturnsToItsSelection() {
        var motion = PackCarouselMotion()
        motion.reset(to: 2)
        motion.beginDrag()
        motion.drag(translation: 110)
        motion.cancelDrag()
        for _ in 0..<120 { motion.advance(seconds: 1.0 / 60, slotCount: 6) }
        #expect(motion.position == 2)
        #expect(!motion.isDragging && !motion.isSettling)
    }

    @Test func longDragsAndLateFramesStayFinite() {
        var motion = PackCarouselMotion()
        motion.beginDrag()
        motion.endDrag(translation: -760, velocity: -3000)
        #expect(motion.target == 4)
        motion.advance(seconds: 2, slotCount: 6)
        #expect(motion.position == 4)
        #expect(!motion.isSettling)
        #expect(PackCarouselMotion.slotCount(museumCount: 0) == 0)
        #expect(PackCarouselMotion.slotCount(museumCount: 1) == 1)
        #expect(PackCarouselMotion.slotCount(museumCount: 3) == 6)
    }
}
