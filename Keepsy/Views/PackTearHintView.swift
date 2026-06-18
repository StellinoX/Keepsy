import SwiftUI

struct PackTearHintView: View {
    let museumId: String
    var packetZoom: CGFloat = 2.0

    @State private var shimmerX: CGFloat = -180
    @State private var glowOpacity: Double = 0.2
    @State private var handOffset: CGFloat = -40
    @State private var textOpacity: Double = 1.0

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ZStack {
                VStack(spacing: 6) {
                    Text("SWIPE RIGHT")
                        .font(.custom("Helvetica-BoldOblique", size: 20))
                        .foregroundStyle(Color(hex: "FF7A00"))
                        .italic()
                        .bold()
                        .shadow(color: Color(hex: "FF7A00").opacity(0.3), radius: 4)

                    Text("TO OPEN")
                        .font(.custom("Helvetica-BoldOblique", size: 20))
                        .foregroundStyle(Color(hex: "FF7A00"))
                        .italic()
                        .bold()
                        .shadow(color: Color(hex: "FF7A00").opacity(0.3), radius: 4)

                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.8))
                        .offset(x: handOffset)
                        .padding(.top, 4)
                }
                .opacity(textOpacity)
                .position(x: screenWidth / 2, y: screenHeight * 0.27)

                ZStack {
                    Rectangle()
                        .fill(Color(hex: "FF7A00").opacity(0.55))
                        .frame(maxWidth: .infinity, maxHeight: 12)
                        .blur(radius: 5)
                        .opacity(glowOpacity)

                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "FF7A00").opacity(0.85), Color(hex: "FF7A00").opacity(1.0), Color(hex: "FF7A00").opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity, maxHeight: 4)
                        .opacity(glowOpacity)

                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color.white.opacity(0.95), Color.white, Color.white.opacity(0.95), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity, maxHeight: 1.5)
                        .opacity(glowOpacity)

                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "FFB800"), Color(hex: "FFB800"), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 110, height: 3)
                        .blur(radius: 1)
                        .offset(x: shimmerX)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 8)
                .clipped()
                .padding(.horizontal, 24)
                .position(x: screenWidth / 2, y: screenHeight * 0.5 + (screenHeight * 0.05) * (packetZoom / 2.0) + ((museumId == "capodimonte" || museumId == "uffizi") ? -13 : 0))
            }
            .frame(width: screenWidth, height: screenHeight)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerX = 180
                }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.9
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    handOffset = 40
                }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    textOpacity = 0.25
                }
            }
        }
    }
}
