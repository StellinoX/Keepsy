import SwiftUI

struct SparkParticle: Identifiable {
    let id = UUID()
    let size: CGFloat
    let angle: Double
    let speed: CGFloat
    let color: Color
}

struct PackOpeningFlashView: View {
    var isTriggered: Bool
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstScale: CGFloat = 0.1
    @State private var burstOpacity: Double = 0.0
    @State private var rayRotation: Double = 0
    @State private var rayRotation2: Double = 0
    @State private var rayOpacity: Double = 0.0
    @State private var rayScale: CGFloat = 0.3
    @State private var ring1Scale: CGFloat = 0.1
    @State private var ring1Opacity: Double = 0.0
    @State private var ring2Scale: CGFloat = 0.1
    @State private var ring2Opacity: Double = 0.0
    @State private var sparkOpacity: Double = 0.0
    @State private var sparkScale: CGFloat = 0.15
    @State private var globalOpacity: Double = 0.0
    @State private var particles: [SparkParticle] = []

    private let goldColors: [Color] = [
        Color(hex: "F5E480"), Color(hex: "FFFFFF"),
        Color(hex: "F1B40A"), Color(hex: "FFD050"),
        Color(hex: "C8860A"), Color(hex: "FFFFFF"),
    ]

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.98),
                    Color(hex: "F5E480").opacity(0.95),
                    Color(hex: "F1B40A").opacity(0.65),
                    Color(hex: "9A6F00").opacity(0.3),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .blendMode(.screen)

            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "F5E480").opacity(0.35), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 1.5 + CGFloat(i % 3) * 1.0, height: 750)
                        .rotationEffect(.degrees(Double(i) * 22.5))
                }
            }
            .drawingGroup()
            .rotationEffect(.degrees(rayRotation))
            .blur(radius: 1.5)
            .scaleEffect(rayScale)
            .opacity(rayOpacity)
            .blendMode(.screen)

            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "FFAC1C").opacity(0.25), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 2.0 + CGFloat(i % 2) * 1.5, height: 700)
                        .rotationEffect(.degrees(Double(i) * 30.0))
                }
            }
            .drawingGroup()
            .rotationEffect(.degrees(rayRotation2))
            .blur(radius: 2.0)
            .scaleEffect(rayScale * 0.9)
            .opacity(rayOpacity * 0.8)
            .blendMode(.screen)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 4.0
                )
                .frame(width: 190, height: 190)
                .scaleEffect(ring1Scale)
                .opacity(ring1Opacity)
                .blur(radius: 1.0)
                .blendMode(.screen)

            Circle()
                .stroke(Color(hex: "FFAC1C").opacity(0.4), lineWidth: 2.5)
                .frame(width: 290, height: 290)
                .scaleEffect(ring2Scale)
                .opacity(ring2Opacity)
                .blur(radius: 2.5)
                .blendMode(.screen)

            ZStack {
                ForEach(particles) { p in
                    let distance = p.speed * 320.0 * sparkScale
                    Circle()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .offset(x: cos(p.angle) * distance,
                                y: sin(p.angle) * distance)
                }
            }
            .drawingGroup()
            .blur(radius: 1.0)
            .opacity(sparkOpacity)
            .blendMode(.screen)
        }
        .opacity(globalOpacity)
        .ignoresSafeArea()
        .onChange(of: isTriggered) { _, newValue in
            if newValue {
                if reduceMotion {
                    onComplete()
                } else {
                    runAnimation()
                }
            }
        }
    }

    func runAnimation() {
        burstScale = 0.1
        burstOpacity = 1.0
        rayScale = 0.3
        rayOpacity = 1.0
        rayRotation = 0
        rayRotation2 = 0
        ring1Scale = 0.1
        ring1Opacity = 1.0
        ring2Scale = 0.1
        ring2Opacity = 0.8
        sparkScale = 0.1
        sparkOpacity = 1.0

        self.particles = (0..<24).map { i in
            let angle = Double.random(in: 0...(2 * Double.pi))
            let size = CGFloat.random(in: 3...9)
            let speed = CGFloat.random(in: 0.6...1.4)
            let colors: [Color] = [
                Color(hex: "FFF9D6"), Color(hex: "F5E480"),
                Color(hex: "F1B40A"), Color(hex: "FFAC1C"),
                Color(hex: "FF7F50"), Color(white: 1.0)
            ]
            let color = colors[i % colors.count]
            return SparkParticle(size: size, angle: angle, speed: speed, color: color)
        }

        globalOpacity = 1.0

        withAnimation(.easeOut(duration: 0.68)) { burstScale = 3.5; burstOpacity = 0.0 }
        withAnimation(.easeOut(duration: 0.75)) { rayScale = 2.4; rayOpacity = 0.0 }
        withAnimation(.easeOut(duration: 0.82)) { rayRotation = 270; rayRotation2 = -320 }
        withAnimation(.easeOut(duration: 0.7)) { ring1Scale = 5.2; ring1Opacity = 0.0 }
        withAnimation(.easeOut(duration: 0.78).delay(0.04)) { ring2Scale = 6.2; ring2Opacity = 0.0 }
        withAnimation(.easeOut(duration: 0.72)) { sparkScale = 1.3; sparkOpacity = 0.0 }
        withAnimation(.easeIn(duration: 0.2).delay(0.65)) { globalOpacity = 0.0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            onComplete()
        }
    }
}
