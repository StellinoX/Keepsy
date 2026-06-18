import SwiftUI

struct PacketFoilImageView: View {
    let imageName: String
    var maxHeight: CGFloat = 225

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(sin(time * 0.72)) * 0.82

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .overlay(
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height

                        ZStack {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.04),
                                    Color(red: 0.78, green: 0.82, blue: 0.86).opacity(0.10),
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
                                            .white.opacity(0.22),
                                            Color(red: 0.72, green: 0.76, blue: 0.80).opacity(0.14),
                                            .white.opacity(0.03),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: w * 0.34, height: h * 1.35)
                                .rotationEffect(.degrees(18))
                                .offset(x: phase * w)
                                .blur(radius: 9)
                                .blendMode(.screen)
                                .opacity(0.55)
                        }
                    }
                    .allowsHitTesting(false)
                )
                .mask(
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: maxHeight)
                )
        }
    }
}
