import CoreGraphics
import Foundation

/// A vector adaptation of the 1€ filter: https://gery.casiez.net/1euro/
/// Tilt is normalized to -1...1. Both axes share the speed-based cutoff so
/// diagonal movements receive the same smoothing in each direction.
struct CardMotionFilter {
    private let minimumCutoff: Double
    private let speedCoefficient: Double
    private let derivativeCutoff: Double
    private var previousInput: CGSize?
    private var output: CGSize = .zero
    private var velocity: CGSize = .zero
    private var previousTimestamp: TimeInterval?

    init(minimumCutoff: Double = 3, speedCoefficient: Double = 6, derivativeCutoff: Double = 2) {
        precondition(minimumCutoff > 0 && speedCoefficient >= 0 && derivativeCutoff > 0)
        self.minimumCutoff = minimumCutoff
        self.speedCoefficient = speedCoefficient
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func reset() {
        previousInput = nil
        previousTimestamp = nil
        velocity = .zero
        output = .zero
    }

    mutating func sample(_ input: CGSize, timestamp: TimeInterval) -> CGSize {
        guard input.width.isFinite, input.height.isFinite, timestamp.isFinite else { return output }
        guard let previousInput, let previousTimestamp else {
            return seed(input, timestamp: timestamp)
        }
        let elapsed = timestamp - previousTimestamp
        guard elapsed > 0 else { return output }
        // A stalled render loop must not carry stale velocity into the next frame.
        guard elapsed <= 0.25 else { return seed(input, timestamp: timestamp) }

        let derivative = CGSize(
            width: (input.width - previousInput.width) / elapsed,
            height: (input.height - previousInput.height) / elapsed
        )
        velocity = blend(velocity, derivative, amount: alpha(cutoff: derivativeCutoff, elapsed: elapsed))
        let cutoff = minimumCutoff + speedCoefficient * hypot(velocity.width, velocity.height)
        output = blend(output, input, amount: alpha(cutoff: cutoff, elapsed: elapsed))
        self.previousInput = input
        self.previousTimestamp = timestamp
        return output
    }

    private mutating func seed(_ input: CGSize, timestamp: TimeInterval) -> CGSize {
        previousInput = input
        previousTimestamp = timestamp
        velocity = .zero
        output = input
        return input
    }

    private func alpha(cutoff: Double, elapsed: TimeInterval) -> Double {
        1 / (1 + 1 / (2 * .pi * cutoff * elapsed))
    }

    private func blend(_ current: CGSize, _ target: CGSize, amount: Double) -> CGSize {
        CGSize(
            width: current.width + (target.width - current.width) * amount,
            height: current.height + (target.height - current.height) * amount
        )
    }
}
