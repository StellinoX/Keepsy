import Foundation

/// Presentation position is also the drag position: there is no hidden SwiftUI
/// animation target to jump to when a second gesture interrupts a settle.
struct PackCarouselMotion {
    static let spacing: CGFloat = 190

    private(set) var position: CGFloat = 0
    private(set) var target: Int = 0
    private(set) var isDragging = false
    private(set) var isSettling = false
    private var dragOrigin: CGFloat = 0
    private var dragTarget = 0
    private var velocity: CGFloat = 0

    static func wrapped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }

    // Two copies per museum keep the outgoing previous pack and the incoming
    // next pack alive simultaneously. Recycling happens beyond the fade at ±2.
    static func slotCount(museumCount: Int) -> Int {
        museumCount > 1 ? max(6, museumCount * 2) : museumCount
    }

    static func distance(slot: Int, position: CGFloat, slotCount: Int) -> CGFloat {
        guard slotCount > 1 else { return 0 }
        let period = CGFloat(slotCount)
        var distance = (CGFloat(slot) - position).truncatingRemainder(dividingBy: period)
        if distance > period / 2 { distance -= period }
        if distance < -period / 2 { distance += period }
        return distance
    }

    mutating func reset(to index: Int) {
        target = index
        position = CGFloat(index)
        velocity = 0
        isDragging = false
        isSettling = false
    }

    mutating func beginDrag() {
        dragOrigin = position
        dragTarget = target
        velocity = 0
        isSettling = false
        isDragging = true
    }

    mutating func drag(translation: CGFloat) {
        guard isDragging else { return }
        position = dragOrigin - translation / Self.spacing
    }

    mutating func endDrag(translation: CGFloat, velocity pointsPerSecond: CGFloat) {
        guard isDragging else { return }
        drag(translation: translation)
        let predicted = translation + pointsPerSecond * 0.2
        let direction: Int
        if translation < -50 || (translation <= 0 && predicted < -200) {
            direction = 1
        } else if translation > 50 || (translation >= 0 && predicted > 200) {
            direction = -1
        } else {
            direction = 0
        }

        var destination = dragTarget + direction
        if direction > 0 { destination = max(destination, Int(position.rounded())) }
        if direction < 0 { destination = min(destination, Int(position.rounded())) }
        isDragging = false
        settle(to: destination)
        // Preserve release momentum only when it leads towards the destination.
        let releaseVelocity = -pointsPerSecond / Self.spacing
        if releaseVelocity * (CGFloat(target) - position) > 0 {
            velocity = min(max(releaseVelocity, -12), 12)
        }
    }

    mutating func cancelDrag() {
        guard isDragging else { return }
        isDragging = false
        settle(to: dragTarget)
    }

    mutating func select(index: Int, museumCount: Int) {
        guard museumCount > 0 else { return }
        var delta = Self.wrapped(index - target, count: museumCount)
        if delta > museumCount / 2 { delta -= museumCount }
        guard delta != 0 else { return }
        isDragging = false
        settle(to: target + delta)
    }

    private mutating func settle(to destination: Int) {
        target = destination
        velocity = 0
        isSettling = true
    }

    mutating func advance(seconds: TimeInterval, slotCount: Int) {
        guard isSettling else { return }
        // Exact critically damped spring, stable even when a frame arrives late.
        let dt = CGFloat(max(0, seconds))
        let frequency: CGFloat = 24
        let displacement = position - CGFloat(target)
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * dt)
        position = CGFloat(target) + (displacement + coefficient * dt) * decay
        velocity = (velocity - frequency * coefficient * dt) * decay

        if abs(position - CGFloat(target)) < 0.001 && abs(velocity) < 0.01 {
            // Bound the numbers without changing any slot's visible position.
            reset(to: Self.wrapped(target, count: slotCount))
        }
    }
}
