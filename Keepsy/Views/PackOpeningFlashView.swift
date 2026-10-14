import SwiftUI

private struct PackBurstParticle: Identifiable {
    let id: Int
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let length: CGFloat
    let delay: Double
    let color: Color
}

struct PackOpeningFlashView: View {
    var isTriggered: Bool
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var impactOpacity = 0.0
    @State private var coreScale: CGFloat = 0.08
    @State private var coreOpacity = 0.0
    @State private var rayScale: CGFloat = 0.2
    @State private var rayRotation = -8.0
    @State private var rayOpacity = 0.0
    @State private var waveScale: CGFloat = 0.05
    @State private var waveOpacity = 0.0
    @State private var secondWaveScale: CGFloat = 0.05
    @State private var secondWaveOpacity = 0.0
    @State private var particleProgress: CGFloat = 0
    @State private var particleOpacity = 0.0
    @State private var globalOpacity = 0.0
    @State private var particles: [PackBurstParticle] = []

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.58

            ZStack {
                Color.white.opacity(impactOpacity).blendMode(.screen)

                radialGlow
                    .scaleEffect(coreScale)
                    .opacity(coreOpacity)

                lightRays(count: 18, color: Color(hex: "FFE892"), length: radius * 1.75)
                    .rotationEffect(.degrees(rayRotation))
                    .scaleEffect(rayScale)
                    .opacity(rayOpacity)

                lightRays(count: 12, color: Color(hex: "FF7A00"), length: radius * 1.5)
                    .rotationEffect(.degrees(-rayRotation * 1.35))
                    .scaleEffect(rayScale * 0.92)
                    .opacity(rayOpacity * 0.7)

                shockwave(size: 170, lineWidth: 5)
                    .scaleEffect(waveScale)
                    .opacity(waveOpacity)

                shockwave(size: 250, lineWidth: 2)
                    .scaleEffect(secondWaveScale)
                    .opacity(secondWaveOpacity)

                particleBurst.opacity(particleOpacity)

                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .scaleEffect(coreScale * 3.2)
                    .opacity(coreOpacity)
                    .blur(radius: 2)
                    .blendMode(.screen)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .drawingGroup()
        }
        .opacity(globalOpacity)
        .ignoresSafeArea()
        .onChange(of: isTriggered) { _, triggered in
            guard triggered else { return }
            runAnimation()
        }
    }

    private var radialGlow: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(hex: "FFF8CF"), location: 0.12),
                    .init(color: Color(hex: "FFD43B").opacity(0.95), location: 0.34),
                    .init(color: Color(hex: "FF7A00").opacity(0.55), location: 0.62),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 180
            ))
            .frame(width: 420, height: 420)
            .blendMode(.screen)
    }

    private var particleBurst: some View {
        ZStack {
            ForEach(particles) { particle in
                let travel = particle.distance * particleProgress
                Capsule()
                    .fill(LinearGradient(
                        colors: [.white, particle.color, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: particle.size, height: particle.length)
                    .rotationEffect(.radians(particle.angle + .pi / 2))
                    .offset(
                        x: CGFloat(cos(particle.angle)) * travel,
                        y: CGFloat(sin(particle.angle)) * travel
                    )
                    .scaleEffect(0.35 + particleProgress * 0.9)
                    .opacity(particleProgress > CGFloat(particle.delay) ? 1 : 0)
            }
        }
        .blendMode(.screen)
    }

    private func lightRays(count: Int, color: Color, length: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(LinearGradient(
                        colors: [.clear, color.opacity(index.isMultiple(of: 3) ? 0.8 : 0.38), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: index.isMultiple(of: 4) ? 4 : 2, height: length)
                    .rotationEffect(.degrees(Double(index) * (360 / Double(count))))
            }
        }
        .blur(radius: 0.8)
        .blendMode(.screen)
    }

    private func shockwave(size: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(AngularGradient(
                colors: [.white, Color(hex: "FFD43B"), Color(hex: "FF7A00"), .white],
                center: .center
            ), lineWidth: lineWidth)
            .frame(width: size, height: size)
            .blur(radius: lineWidth * 0.35)
            .blendMode(.screen)
    }

    private func runAnimation() {
        resetAnimation()
        particles = makeParticles()
        globalOpacity = 1

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                impactOpacity = 0.28
                coreOpacity = 0.65
                coreScale = 1.4
            }
            withAnimation(.easeIn(duration: 0.22).delay(0.18)) { globalOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                onComplete()
            }
            return
        }

        withAnimation(.easeOut(duration: 0.06)) { impactOpacity = 0.92 }
        withAnimation(.easeIn(duration: 0.22).delay(0.06)) { impactOpacity = 0 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) {
            coreScale = 1.15
            coreOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.58).delay(0.12)) {
            coreScale = 3.8
            coreOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.72)) {
            rayScale = 2.25
            rayRotation = 22
            rayOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.52)) {
            waveScale = 4.4
            waveOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.68).delay(0.08)) {
            secondWaveScale = 4.8
            secondWaveOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.74)) { particleProgress = 1 }
        withAnimation(.easeIn(duration: 0.22).delay(0.48)) { particleOpacity = 0 }
        withAnimation(.easeIn(duration: 0.18).delay(0.7)) { globalOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            onComplete()
        }
    }

    private func resetAnimation() {
        impactOpacity = 0
        coreScale = 0.08
        coreOpacity = 1
        rayScale = 0.2
        rayRotation = -8
        rayOpacity = 1
        waveScale = 0.05
        waveOpacity = 1
        secondWaveScale = 0.05
        secondWaveOpacity = 0.75
        particleProgress = 0
        particleOpacity = 1
        globalOpacity = 0
    }

    private func makeParticles() -> [PackBurstParticle] {
        let colors = [Color.white, Color(hex: "FFF8CF"), Color(hex: "FFD43B"), Color(hex: "FF9D19"), Color(hex: "FF6B2C")]
        return (0..<34).map { index in
            let baseAngle = (Double(index) / 34) * 2 * Double.pi
            return PackBurstParticle(
                id: index,
                angle: baseAngle + Double.random(in: -0.08...0.08),
                distance: CGFloat.random(in: 115...310),
                size: CGFloat.random(in: 2...6),
                length: CGFloat.random(in: 10...38),
                delay: Double.random(in: 0...0.2),
                color: colors[index % colors.count]
            )
        }
    }
}
