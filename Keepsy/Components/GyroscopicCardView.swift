import SwiftUI

/// Adds device motion to a card without changing its layout or touch gestures.
struct GyroscopicCardView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = CardMotionController()

    @ViewBuilder let content: (CGSize) -> Content

    private var isEnabled: Bool {
        scenePhase == .active && !reduceMotion
    }

    var body: some View {
        let tilt = isEnabled ? motion.tilt : .zero
        let rotation = CardMotionProjection.rotationDegrees(for: tilt)

        content(tilt)
            .rotation3DEffect(.degrees(rotation.x), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
            .rotation3DEffect(.degrees(rotation.y), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
            .task(id: isEnabled) {
                if isEnabled {
                    await motion.track()
                }
            }
    }
}

extension View {
    func gyroscopicCardMotion() -> some View {
        GyroscopicCardView { _ in self }
    }
}
