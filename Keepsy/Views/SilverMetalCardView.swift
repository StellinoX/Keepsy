import SwiftUI

/// A restrained metallic finish that keeps the card artwork readable.
struct SilverMetalCardView<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let isEnabled: Bool
    let tiltX: Double
    let tiltY: Double
    let customRotationX: Double?
    let customRotationY: Double?
    let content: () -> Content

    init(
        width: CGFloat = 260,
        height: CGFloat = 390,
        isEnabled: Bool = true,
        tiltX: Double = 0,
        tiltY: Double = 0,
        customRotationX: Double? = nil,
        customRotationY: Double? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.isEnabled = isEnabled
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.customRotationX = customRotationX
        self.customRotationY = customRotationY
        self.content = content
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(sin(time * 0.72)) * 0.82

            ZStack {
                content()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                if isEnabled {
                    SilverMetalOverlay(phase: phase, tiltX: tiltX, tiltY: tiltY)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
            .rotation3DEffect(.degrees(customRotationX ?? (tiltY * -8)), axis: (x: 1, y: 0, z: 0), perspective: 0.75)
            .rotation3DEffect(.degrees(customRotationY ?? (tiltX * 8)), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
            .shadow(color: .white.opacity(isEnabled ? 0.14 : 0.08), radius: isEnabled ? 18 : 10, x: 0, y: 8)
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
        }
    }
}

private struct SilverMetalOverlay: View {
    let phase: CGFloat
    let tiltX: Double
    let tiltY: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.04),
                        Color(red: 0.78, green: 0.82, blue: 0.86).opacity(0.12),
                        .white.opacity(0.05),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.03),
                                .white.opacity(0.30),
                                Color(red: 0.72, green: 0.76, blue: 0.80).opacity(0.18),
                                .white.opacity(0.03),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.34, height: height * 1.35)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * width + (tiltX * width * 0.22), y: tiltY * height * 0.05)
                    .blur(radius: 9)
                    .blendMode(.screen)
                    .opacity(0.62 + min(abs(tiltX), 1.0) * 0.24)

                LinearGradient(
                    colors: [
                        .white.opacity(0.16),
                        .clear,
                        .black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
            }
        }
    }
}
