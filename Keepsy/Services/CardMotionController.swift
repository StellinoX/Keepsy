import CoreGraphics
import CoreMotion
import Foundation
import Observation
import QuartzCore
import simd

/// Calibrates to the way the phone is held when a full-screen card appears.
@MainActor
@Observable
final class CardMotionController: NSObject {
    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var activeSession: UUID?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var reference: simd_quatd?
    @ObservationIgnored private var lastTimestamp: TimeInterval = 0
    @ObservationIgnored private var targetTilt: CGSize = .zero
    @ObservationIgnored private var filter = CardMotionFilter()

    func track() async {
        guard manager.isDeviceMotionAvailable, !Task.isCancelled else { return }

        let session = UUID()
        activeSession = session
        lastTimestamp = ProcessInfo.processInfo.systemUptime
        reference = nil
        targetTilt = .zero
        filter.reset()
        manager.deviceMotionUpdateInterval = 1.0 / 120.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(updateMotion(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link

        defer {
            if activeSession == session {
                displayLink?.invalidate()
                displayLink = nil
                manager.stopDeviceMotionUpdates()
                activeSession = nil
                reference = nil
                targetTilt = .zero
                filter.reset()
                tilt = .zero
            }
        }

        while !Task.isCancelled && activeSession == session {
            do {
                // The display link drives rendering; this task owns its lifetime.
                try await Task.sleep(for: .seconds(60))
            } catch {
                break
            }
        }
    }

    @objc private func updateMotion(_ link: CADisplayLink) {
        // Sensor delivery and display refresh need not have the same frequency.
        // Read fresh data when available, but advance the filter on every frame.
        if let sample = manager.deviceMotion, sample.timestamp > lastTimestamp {
            lastTimestamp = sample.timestamp
            let q = sample.attitude.quaternion
            let current = simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w)
            if reference == nil { reference = current }
            if let reference {
                targetTilt = CardMotionProjection.tilt(current: current, relativeTo: reference)
            }
        }
        guard reference != nil else { return }
        tilt = filter.sample(targetTilt, timestamp: link.targetTimestamp)
    }
}
