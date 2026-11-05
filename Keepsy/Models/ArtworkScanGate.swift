import Foundation

/// Shared by every reference variant of an artwork. Rejected detections never
/// consume an unlock, and updates can retry an anchor after the animation cooldown.
nonisolated struct ArtworkScanGate {
    private(set) var selectionID = UUID()
    private(set) var targetName: String
    private var deliveredNames: Set<String> = []
    private var nextDetectionTime = -TimeInterval.infinity

    init(targetName: String) {
        self.targetName = targetName
    }

    mutating func select(_ name: String) {
        guard name != targetName else { return }
        targetName = name
        invalidatePendingDetections()
    }

    mutating func invalidatePendingDetections() {
        selectionID = UUID()
    }

    func canTrack(artworkName: String) -> Bool {
        (targetName.isEmpty || artworkName == targetName) && !deliveredNames.contains(artworkName)
    }

    mutating func accept(
        artworkName: String,
        selectionID: UUID,
        time: TimeInterval
    ) -> Bool {
        guard selectionID == self.selectionID,
              canTrack(artworkName: artworkName),
              time >= nextDetectionTime,
              time.isFinite else { return false }
        deliveredNames.insert(artworkName)
        nextDetectionTime = time + 4
        return true
    }
}
