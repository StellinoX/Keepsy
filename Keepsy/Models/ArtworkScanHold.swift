import Foundation

/// Capture requires fresh camera observations throughout the entire hold.
/// Time alone can never complete a scan after the artwork has disappeared.
nonisolated struct ArtworkScanHold {
    static let duration: TimeInterval = 2
    static let maximumFrameGap: TimeInterval = 0.25

    struct Progress: Equatable, Sendable {
        let artworkName: String?
        let fraction: Double
        static let idle = Progress(artworkName: nil, fraction: 0)
        var isComplete: Bool { fraction >= 1 }
    }

    private(set) var progress: Progress = .idle
    private var startedAt: TimeInterval?
    private var lastObservation: TimeInterval?

    mutating func reset() {
        progress = .idle
        startedAt = nil
        lastObservation = nil
    }

    mutating func observe(visibleNames: Set<String>, time: TimeInterval) -> Progress {
        guard time.isFinite else { reset(); return progress }
        // Ignore out-of-order frames rather than letting an old frame finish a hold.
        if let lastObservation, time <= lastObservation { return progress }
        if let lastObservation, time - lastObservation > Self.maximumFrameGap { reset() }
        guard let name = progress.artworkName.flatMap({ visibleNames.contains($0) ? $0 : nil })
                ?? visibleNames.sorted().first else {
            reset()
            return progress
        }
        if name != progress.artworkName {
            startedAt = time
        }
        lastObservation = time
        let fraction = min(1, max(0, (time - (startedAt ?? time)) / Self.duration))
        progress = Progress(artworkName: name, fraction: fraction)
        return progress
    }
}
