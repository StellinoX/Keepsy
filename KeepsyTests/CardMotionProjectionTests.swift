import CoreGraphics
import Foundation
import Testing
import simd
@testable import Keepsy

@Suite
@MainActor
struct CardMotionProjectionTests {
    private func quaternion(_ degrees: Double, axis: SIMD3<Double>) -> simd_quatd {
        simd_quatd(angle: degrees * .pi / 180, axis: axis)
    }

    private func rotation(_ device: simd_quatd) -> SIMD2<Double> {
        CardMotionProjection.rotationDegrees(for: CardMotionProjection.tilt(for: device))
    }

    @Test func phoneTopMovingTowardsViewerBringsCardTopTowardsViewer() {
        for angle in [-10.0, 10.0] {
            let angles = rotation(quaternion(angle, axis: SIMD3(1, 0, 0)))
            #expect(abs(angles.x + angle * 0.8) < 0.000001)
            #expect(abs(angles.y) < 0.000001)
            let screen = quaternion(angles.x, axis: SIMD3(1, 0, 0))
            // SwiftUI's top edge has negative Y. Positive Z is towards us.
            let topEdge = screen.act(SIMD3<Double>(0, -1, 0))
            #expect(topEdge.z * angle > 0)
        }
    }

    @Test func phoneRightEdgeMovingAwayMovesCardRightEdgeAway() {
        for angle in [-10.0, 10.0] {
            let angles = rotation(quaternion(angle, axis: SIMD3(0, 1, 0)))
            #expect(abs(angles.x) < 0.000001)
            #expect(abs(angles.y - angle * 0.8) < 0.000001)
            let screen = quaternion(angles.y, axis: SIMD3(0, 1, 0))
            let rightEdge = screen.act(SIMD3<Double>(1, 0, 0))
            #expect(rightEdge.z * angle < 0)
        }
    }

    @Test func diagonalMovementsDoNotAmplifyTheOtherAxis() {
        for pitch in [-12.0, 12.0] {
            for yaw in [-15.0, 15.0] {
                let device = quaternion(yaw, axis: SIMD3(0, 1, 0))
                    * quaternion(pitch, axis: SIMD3(1, 0, 0))
                let angles = rotation(device)
                #expect(abs(angles.x + pitch * 0.8) < 0.000001)
                #expect(abs(angles.y - yaw * 0.8) < 0.000001)
            }
        }
    }

    @Test func sameMovementHasSameAxesWhenOpenedUprightOrReclined() {
        let local = quaternion(9, axis: SIMD3(0, 1, 0))
            * quaternion(-7, axis: SIMD3(1, 0, 0))
        let expected = rotation(local)
        for pitch in [0.0, 45.0, 90.0] {
            for heading in [-70.0, 0.0, 100.0] {
                let reference = quaternion(heading, axis: SIMD3(0, 0, 1))
                    * quaternion(pitch, axis: SIMD3(1, 0, 0))
                let tilt = CardMotionProjection.tilt(current: reference * local, relativeTo: reference)
                let angles = CardMotionProjection.rotationDegrees(for: tilt)
                #expect(abs(angles.x - expected.x) < 0.000001)
                #expect(abs(angles.y - expected.y) < 0.000001)
                let neutral = CardMotionProjection.tilt(current: reference, relativeTo: reference)
                #expect(abs(neutral.width) < 0.000001 && abs(neutral.height) < 0.000001)
            }
        }
    }

    @Test func inPlaneTwistDoesNotIntroduceDepthTilt() {
        for angle in [-90.0, -30.0, 0.0, 30.0, 90.0] {
            let angles = rotation(quaternion(angle, axis: SIMD3(0, 0, 1)))
            #expect(abs(angles.x) < 0.000001 && abs(angles.y) < 0.000001)
        }
    }

    @Test func smallMovementsRespondAndLargeOnesStayBounded() {
        let small = rotation(quaternion(0.25, axis: SIMD3(0, 1, 0)))
        #expect(abs(small.y - 0.2) < 0.000001)
        for angle in [-70.0, 70.0] {
            let angles = rotation(quaternion(angle, axis: SIMD3(1, 0, 0)))
            #expect(abs(abs(angles.x) - 16) < 0.000001)
            #expect(abs(angles.y) < 0.000001)
        }
    }

    @Test func inclinationApproachesItsLimitGradually() {
        let angles = [15.0, 19.0, 20.0, 21.0, 25.0, 30.0].map {
            rotation(quaternion($0, axis: SIMD3(0, 1, 0))).y
        }
        for index in 1..<angles.count {
            #expect(angles[index] > angles[index - 1])
            #expect(angles[index] < 16)
        }
        // Crossing the former 20-degree clamp still produces a smooth response.
        #expect(angles[3] - angles[2] > 0.05)
        #expect(angles[3] - angles[2] < angles[2] - angles[1])
    }
}
