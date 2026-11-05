import CoreGraphics
import Foundation
import Testing
@testable import Keepsy

@Suite
@MainActor
struct CardMotionFilterTests {
    @Test func stationaryHandRemainsStill() {
        var filter = CardMotionFilter()
        let pose = CGSize(width: 0.3, height: -0.2)
        for frame in 0..<240 {
            #expect(filter.sample(pose, timestamp: Double(frame) / 120) == pose)
        }
    }

    @Test func handJitterIsLowerThanThePreviousFixedFilter() {
        var filter = CardMotionFilter()
        _ = filter.sample(.zero, timestamp: 0)
        var previousOutput = 0.0
        var adaptiveEnergy = 0.0
        var previousEnergy = 0.0
        let previousBlend = 1 - exp(-(1.0 / 60) / 0.025)
        for frame in 1...240 {
            let input = frame.isMultiple(of: 2) ? 0.005 : -0.005
            let output = filter.sample(CGSize(width: input, height: 0), timestamp: Double(frame) / 60)
            previousOutput += (input - previousOutput) * previousBlend
            if frame > 120 {
                adaptiveEnergy += output.width * output.width
                previousEnergy += previousOutput * previousOutput
            }
        }
        #expect(adaptiveEnergy < previousEnergy * 0.7)
    }

    @Test func fastHandMovementHasLessLagThanThePreviousFixedFilter() {
        var filter = CardMotionFilter()
        _ = filter.sample(.zero, timestamp: 0)
        var previousOutput = 0.0
        var adaptiveLag = 0.0
        var previousLag = 0.0
        let previousBlend = 1 - exp(-(1.0 / 60) / 0.025)
        for frame in 1...12 {
            let input = Double(frame) / 15
            let output = filter.sample(CGSize(width: input, height: 0), timestamp: Double(frame) / 60)
            previousOutput += (input - previousOutput) * previousBlend
            adaptiveLag += input - output.width
            previousLag += input - previousOutput
        }
        #expect(adaptiveLag < previousLag * 0.8)
    }

    @Test func diagonalMotionKeepsItsDirectionDuringSmoothing() {
        var filter = CardMotionFilter()
        _ = filter.sample(.zero, timestamp: 0)
        for frame in 1...40 {
            let x = Double(frame) / 50
            let output = filter.sample(CGSize(width: x, height: -x * 0.5), timestamp: Double(frame) / 120)
            #expect(abs(output.height + output.width * 0.5) < 0.000001)
        }
    }

    @Test func differentRefreshRatesProduceSimilarMotion() {
        func replay(rate: Int) -> [Double] {
            var filter = CardMotionFilter()
            return (0...(rate * 2)).map { frame in
                let time = Double(frame) / Double(rate)
                let input = CGSize(width: sin(time * .pi * 1.5) * 0.6, height: 0)
                return filter.sample(input, timestamp: time).width
            }
        }
        let at60 = replay(rate: 60)
        let at120 = replay(rate: 120)
        let maximumDifference = at60.indices.map { abs(at60[$0] - at120[$0 * 2]) }.max() ?? 0
        #expect(maximumDifference < 0.035)
    }

    @Test func displayFramesBetweenSensorSamplesContinueMoving() {
        var filter = CardMotionFilter()
        _ = filter.sample(.zero, timestamp: 0)
        let target = CGSize(width: 0.5, height: 0)
        let firstFrame = filter.sample(target, timestamp: 1.0 / 120)
        let secondFrame = filter.sample(target, timestamp: 2.0 / 120)
        #expect(firstFrame.width > 0)
        #expect(secondFrame.width > firstFrame.width && secondFrame.width < target.width)
    }

    @Test func reversalsNeverOvershootAndResetClearsMomentum() {
        var filter = CardMotionFilter()
        _ = filter.sample(.zero, timestamp: 0)
        for frame in 1...240 {
            let input = frame < 120 ? 0.8 : -0.8
            let output = filter.sample(CGSize(width: input, height: -input), timestamp: Double(frame) / 120)
            #expect(abs(output.width) <= 0.8 && abs(output.height) <= 0.8)
        }
        filter.reset()
        #expect(filter.sample(.zero, timestamp: 10) == .zero)
        #expect(filter.sample(.zero, timestamp: 10.01) == .zero)
    }

    @Test func invalidSamplesDoNotPoisonTheFilterAndLongPausesClearVelocity() {
        var filter = CardMotionFilter()
        let initial = CGSize(width: 0.1, height: -0.1)
        #expect(filter.sample(initial, timestamp: 1) == initial)
        #expect(filter.sample(.zero, timestamp: 1) == initial)
        #expect(filter.sample(.zero, timestamp: 0.5) == initial)
        #expect(filter.sample(CGSize(width: Double.nan, height: 0), timestamp: 1.01) == initial)
        #expect(filter.sample(.zero, timestamp: .infinity) == initial)
        #expect(filter.sample(.zero, timestamp: 2) == .zero)
    }
}
