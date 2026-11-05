import CoreGraphics
import Foundation
import simd

/// Converts Core Motion's device axes into SwiftUI's screen rotation axes.
enum CardMotionProjection {
    static let maximumRotationDegrees = 16.0
    private static let physicalRange = Double.pi / 9

    static func tilt(current: simd_quatd, relativeTo reference: simd_quatd) -> CGSize {
        tilt(for: simd_inverse(reference) * current)
    }

    static func tilt(for deviceRotation: simd_quatd) -> CGSize {
        let device = simd_normalize(deviceRotation)
        // Core Motion and SwiftUI share Y, but their X and Z rotation axes
        // have opposite signs. Convert the entire rotation before projecting.
        let screen = simd_quatd(
            ix: -device.imag.x, iy: device.imag.y, iz: -device.imag.z, r: device.real
        )
        let normal = screen.act(SIMD3<Double>(0, 0, 1))
        // Match the view's X-then-Y rotation order. Using normal.z alone for
        // pitch incorrectly adds vertical tilt during a diagonal movement.
        let pitch = atan2(-normal.y, hypot(normal.x, normal.z))
        let yaw = atan2(normal.x, normal.z)
        return CGSize(
            width: softLimit(yaw / physicalRange),
            height: softLimit(-pitch / physicalRange)
        )
    }

    static func rotationDegrees(for tilt: CGSize) -> SIMD2<Double> {
        SIMD2(-tilt.height * maximumRotationDegrees, tilt.width * maximumRotationDegrees)
    }

    private static func softLimit(_ value: Double) -> Double {
        let start = 0.75
        guard abs(value) > start else { return value }
        let magnitude = start + (1 - start) * tanh((abs(value) - start) / (1 - start))
        return value < 0 ? -magnitude : magnitude
    }
}
