import SwiftUI

struct PackSelectionView: View {
    let museumId: String
    let onPacketSelected: () -> Void
    let onClose: () -> Void
    
    @State private var selectedIndex: Int? = nil
    @State private var isOpening = false
    
    private let totalPacks = 6
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let safeTop = geometry.safeAreaInsets.top
            let packWidth = screenWidth * 1.15
            let packHeight = packWidth * (350.0 / 230.0) // Aspect ratio of the packet assets
            
            let spacing = packHeight * 0.125
            let totalSpacing = spacing * CGFloat(totalPacks - 1)
            
            ZStack {
                // Background Gradient
                LinearGradient(
                    colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                GridBackground()
                    .opacity(0.4)
                
                // Packets Stack — visuals only (hit testing disabled)
                ZStack {
                    ForEach(0..<totalPacks, id: \.self) { i in
                        let isSelected = selectedIndex == i
                        
                        let zIndex: Double = {
                            if isOpening && isSelected { return 100.0 }
                            return Double(totalPacks - 1 - i)
                        }()
                        
                        let progress = CGFloat(i) / CGFloat(totalPacks - 1)
                        let idleScale = 1.45 - progress * 0.15
                        let stackBaseCenter = screenHeight * 0.16
                        let idleYOffset = stackBaseCenter + (0.5 - progress) * totalSpacing

                        let scale: CGFloat = {
                            if isOpening { return isSelected ? 1.18 : 0.0 }
                            return idleScale
                        }()
                        let yOffset: CGFloat = {
                            if isOpening {
                                return isSelected ? screenHeight * 0.26 : screenHeight * 1.2
                            }
                            return isSelected ? idleYOffset - 90 : idleYOffset
                        }()
                        let opacity: Double = isOpening ? (isSelected ? 1.0 : 0.0) : 1.0
                        let colorMultiplier: Color = isSelected ? .white : Color(white: 0.35)

                        let imageName = MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"

                        SceneKitPacketView(
                            interactive: false,
                            isTorn: false,
                            museumId: museumId,
                            packetImageName: imageName
                        )
                        .frame(width: packWidth, height: packHeight)
                        .colorMultiply(colorMultiplier)
                        .shadow(
                            color: isSelected ? Color(hex: "FF7A00").opacity(0.4) : Color.black.opacity(0.35),
                            radius: isSelected ? 24 : 12,
                            y: isSelected ? 12 : 6
                        )
                        .allowsHitTesting(false)
                        .scaleEffect(scale)
                        .offset(y: yOffset)
                        .opacity(opacity)
                        .zIndex(zIndex)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)

                // Tap overlay ZStack — z-order is REVERSED so back packets get tap priority
                // over the front packet that visually overlaps them
                ZStack {
                    ForEach(0..<totalPacks, id: \.self) { i in
                        let isSelected = selectedIndex == i

                        let progress = CGFloat(i) / CGFloat(totalPacks - 1)
                        let idleScale = 1.45 - progress * 0.15
                        let stackBaseCenter = screenHeight * 0.16
                        let idleYOffset = stackBaseCenter + (0.5 - progress) * totalSpacing

                        let yOffset: CGFloat = {
                            if isOpening {
                                return isSelected ? screenHeight * 0.26 : screenHeight * 1.2
                            }
                            return isSelected ? idleYOffset - 90 : idleYOffset
                        }()
                        let scale: CGFloat = {
                            if isOpening { return isSelected ? 1.18 : 0.0 }
                            return idleScale
                        }()

                        // Reversed z-index: packets further back (higher i) get higher tap priority
                        let tapZIndex = Double(i)

                        Color.clear
                            .frame(width: packWidth, height: packHeight)
                            .contentShape(Rectangle())
                            .scaleEffect(scale)
                            .offset(y: yOffset)
                            .onTapGesture {
                                guard !isOpening else { return }
                                HapticManager.shared.triggerImpact(style: .medium)
                                if selectedIndex == i {
                                    openPacket(index: i)
                                } else {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        selectedIndex = i
                                    }
                                }
                            }
                            .zIndex(tapZIndex)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
                
                // Back button at the top-left (standard design)
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    onClose()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .foregroundColor(.white)
                    .frame(width: 85, height: 44)
                    .background(
                        Capsule().fill(Color(hex: "383838"))
                    )
                }
                .position(x: 30 + 85/2, y: 83 + 44/2)
            }
            .frame(width: screenWidth, height: screenHeight)
        }
        .ignoresSafeArea()
    }
    
    private func openPacket(index: Int) {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            isOpening = true
        }
        
        // Short delay to let the animation complete before transitioning to the tear screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onPacketSelected()
        }
    }
}
