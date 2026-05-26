import SwiftUI
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ArtworkEffect: CaseIterable {
    case pixelate, twirl, bump, hue
}

struct ARArtworkView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var detectedArtwork: String = "Trova l'opera per sbloccarla!"
    @State private var isTargetUnlocked: Bool = false
    @State private var selectedTargetCard: String? = nil
    @GestureState private var gestureDragOffset: CGFloat = 0.0
    
    var revealedCards: Set<String> {
        return CardDatabase.getRevealedCards()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                
                // Camera feed showing AR tracking (fullscreen as before)
                ARViewContainer(
                    detectedArtwork: $detectedArtwork,
                    isTargetUnlocked: $isTargetUnlocked,
                    activeView: $activeView,
                    targetName: selectedTargetCard ?? ""
                )
                .ignoresSafeArea()
                
                // Elegant Back Button (top-left aligned with the specified coordinates)
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        activeView = .opening
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 85, height: 44)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: "E36D13"), Color(hex: "FEBB0B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .shadow(color: Color(hex: "E36D13").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .position(x: 30 + 85/2, y: 83 + 44/2)
                
                // Bottom Overlay: Carousel of cards (if active pack exists)
                VStack(spacing: 12) {
                    Spacer()
                    
                    if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                        // Title/hint
                        Text(isTargetUnlocked ? "✨ OPERA TROVATA! ✨" : "TROVA: \(cleanedArtworkName(selectedTargetCard ?? ""))")
                            .font(.system(size: 14, weight: .black))
                            .italic()
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isTargetUnlocked ? Color.green.opacity(0.8) : Color.black.opacity(0.6)))
                            .padding(.bottom, 12)
                        
                        // Carousel of 5 cards (with overlapping offset, keeping fixed order)
                        let selectedIndex = activePack.firstIndex(of: selectedTargetCard ?? "") ?? 0
                        let spacing: CGFloat = -5
                        let cardWidth: CGFloat = 100
                        let totalWidth = CGFloat(activePack.count) * cardWidth + CGFloat(activePack.count - 1) * spacing
                        let cardCenter = CGFloat(selectedIndex) * (cardWidth + spacing) + (cardWidth / 2)
                        let baseOffset = (screenWidth / 2) - cardCenter
                        
                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(0..<activePack.count, id: \.self) { index in
                                let cardName = activePack[index]
                                let isSelected = cardName == selectedTargetCard
                                let isRevealed = revealedCards.contains(cardName)
                                
                                // Calculate distance from the center of the screen
                                let indexDiff = CGFloat(index - selectedIndex)
                                let cardCenterDiff = cardWidth + spacing
                                let distanceFromCenter = indexDiff * cardCenterDiff + gestureDragOffset
                                
                                // Calculate dynamic scale and zIndex
                                let scale = scaleForDistance(distanceFromCenter)
                                let zIndexVal = 10.0 - (min(abs(distanceFromCenter), 190.0) / 190.0)
                                
                                VStack(spacing: 0) {
                                    ZStack(alignment: .topTrailing) {
                                        let currentCornerRadius = cardWidth * 12.0 / 111.0
                                        
                                        ScannerCardView(
                                            name: cardName,
                                            width: cardWidth,
                                            height: 151.0
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: currentCornerRadius)
                                                .stroke(isSelected ? Color(hex: "F1B40A") : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                                        )
                                        .shadow(color: isSelected ? Color(hex: "F1B40A").opacity(0.4) : .black.opacity(0.3), radius: isSelected ? 15 : 5)
                                        
                                        if isRevealed {
                                            // Checked overlay badge
                                            ZStack {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 28, height: 28)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            .padding(8)
                                        }
                                    }
                                }
                                .scaleEffect(scale)
                                .zIndex(zIndexVal)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedTargetCard != cardName {
                                        HapticManager.shared.triggerSelection()
                                        changeSelection(to: cardName)
                                    }
                                }
                            }
                        }
                        .frame(width: totalWidth)
                        .offset(x: baseOffset + gestureDragOffset)
                        .frame(height: 260)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .updating($gestureDragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onEnded { value in
                                    let dragDistance = value.translation.width
                                    let shift = Int(round(-dragDistance / 95.0))
                                    let newIndex = max(0, min(activePack.count - 1, selectedIndex + shift))
                                    
                                    if newIndex != selectedIndex {
                                        HapticManager.shared.triggerSelection()
                                        changeSelection(to: activePack[newIndex])
                                    }
                                }
                        )
                    } else {
                        // No active pack: show classic scan text
                        Text(detectedArtwork)
                            .font(.headline)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .padding(.bottom, 50)
                    }
                }
                .frame(width: screenWidth)
                .frame(height: screenHeight - 83)
                .position(x: screenWidth / 2, y: 83 + (screenHeight - 83) / 2)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if let active = CardDatabase.getActivePack(), !active.isEmpty {
                // Find the first card that is not yet revealed
                if let target = active.first(where: { !revealedCards.contains($0) }) {
                    selectedTargetCard = target
                } else {
                    selectedTargetCard = active.first
                }
                isTargetUnlocked = revealedCards.contains(selectedTargetCard ?? "")
            }
        }
    }
    
    func cleanedArtworkName(_ name: String) -> String {
        return name
            .replacingOccurrences(of: "__detail_", with: "")
            .replacingOccurrences(of: "_detail_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func scaleForDistance(_ distance: CGFloat) -> CGFloat {
        let maxDistance: CGFloat = 190.0
        let absDistance = min(abs(distance), maxDistance)
        // Interpolate scale from 1.6 (at 0) to 0.8 (at maxDistance)
        return 1.6 - 0.8 * (absDistance / maxDistance)
    }
    
    private func selectNextCard(activePack: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = activePack.firstIndex(of: current) else { return }
        if currentIndex < activePack.count - 1 {
            HapticManager.shared.triggerSelection()
            changeSelection(to: activePack[currentIndex + 1])
        }
    }
    
    private func selectPreviousCard(activePack: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = activePack.firstIndex(of: current) else { return }
        if currentIndex > 0 {
            HapticManager.shared.triggerSelection()
            changeSelection(to: activePack[currentIndex - 1])
        }
    }
    
    private func changeSelection(to cardName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selectedTargetCard = cardName
            isTargetUnlocked = revealedCards.contains(cardName)
            detectedArtwork = isTargetUnlocked ? "Già sbloccata!" : "Trova l'opera per sbloccarla!"
        }
    }
}

// MARK: - Mini Card View for Scanner Carousel (matching packet artwork card design)
struct ScannerCardView: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let gradient = CardDatabase.gradientFor(name: name)
        let imgWidth = width * 101 / 111
        let imgHeight = height * 125 / 168
        let paddingSize = width * 5 / 111
        
        VStack(spacing: 0) {
            Group {
                if UIImage(named: name) != nil {
                    Image(name)
                        .resizable()
                } else {
                    Image("CardBackLogo")
                        .resizable()
                }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: imgWidth, height: imgHeight)
            .cornerRadius(width * 12 / 111)
            .padding(.top, paddingSize)
            .padding(.horizontal, paddingSize)
            
            Spacer()
        }
        .frame(width: width, height: height)
        .background(gradient)
        .cornerRadius(width * 12 / 111)
    }
}

// MARK: - Gestore delle Distorsioni
struct DistortedImageView: View {
    var image: UIImage
    var effect: ArtworkEffect
    
    var body: some View {
        if let result = applyEffect(to: image) {
            Image(uiImage: result)
                .resizable()
                .interpolation(effect == .pixelate ? .none : .high) // Fondamentale per il pixelate
        } else {
            Image(uiImage: image)
                .resizable()
        }
    }
    
    func applyEffect(to input: UIImage) -> UIImage? {
        // Caso speciale per Pixelate: rimpiccioliamo e ingrandiamo
        if effect == .pixelate {
            return input.resize(to: CGSize(width: 20, height: 20))
        }
        
        // Altri effetti con Core Image
        let ciContext = CIContext()
        guard let ciImage = CIImage(image: input) else { return nil }
        var filter: CIFilter?
        
        switch effect {
        case .twirl:
            filter = CIFilter(name: "CITwirlDistortion")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: input.size.width / 2, y: input.size.height / 2), forKey: kCIInputCenterKey)
            filter?.setValue(min(input.size.width, input.size.height) / 2, forKey: kCIInputRadiusKey)
            filter?.setValue(3.0, forKey: kCIInputAngleKey)
            
        case .bump:
            filter = CIFilter(name: "CIBumpDistortion")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(x: input.size.width / 2, y: input.size.height / 2), forKey: kCIInputCenterKey)
            filter?.setValue(min(input.size.width, input.size.height) / 1.2, forKey: kCIInputRadiusKey)
            filter?.setValue(0.7, forKey: kCIInputScaleKey)
            
        case .hue:
            filter = CIFilter(name: "CIHueAdjust")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(2.5, forKey: kCIInputAngleKey)
            
        default: break
        }
        
        guard let output = filter?.outputImage,
              let cgImage = ciContext.createCGImage(output, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// Estensione per il ridimensionamento
extension UIImage {
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var detectedArtwork: String
    @Binding var isTargetUnlocked: Bool
    @Binding var activeView: ContentView.ActiveView
    let targetName: String
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        let configuration = ARImageTrackingConfiguration()
        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
            configuration.trackingImages = referenceImages
            configuration.maximumNumberOfTrackedImages = 1
        }
        arView.session.run(configuration)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        init(parent: ARViewContainer) { self.parent = parent }
        
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let imageAnchor = anchor as? ARImageAnchor else { return }
            let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"
            
            // Il nome del database NON ha il suffisso "_0" o "_1"
            let dbName = rawName.replacingOccurrences(of: "_[0-9]+$", with: "", options: .regularExpression)
            
            let cleanedName = dbName
                .replacingOccurrences(of: "__detail_", with: "")
                .replacingOccurrences(of: "_detail_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            
            DispatchQueue.main.async {
                if self.parent.targetName.isEmpty {
                    // Fallback if no active pack target: unlock any found card
                    if CardDatabase.getFoundCards().contains(dbName) {
                        CardDatabase.addRevealedCard(dbName)
                        self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                        self.parent.isTargetUnlocked = true
                    }
                } else if dbName == self.parent.targetName {
                    CardDatabase.addRevealedCard(dbName)
                    CardDatabase.clearActivePackIfNeeded()
                    self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                    self.parent.isTargetUnlocked = true
                    
                    // Se tutto il pacchetto è stato sbloccato, torna alla home dopo 2 secondi
                    if !CardDatabase.hasActivePack() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                self.parent.activeView = .opening
                            }
                        }
                    }
                } else {
                    let cleanedTargetName = self.parent.targetName
                        .replacingOccurrences(of: "__detail_", with: "")
                        .replacingOccurrences(of: "_detail_", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    self.parent.detectedArtwork = "Non è la carta selezionata! Trova \(cleanedTargetName)."
                }
            }
        }
    }
}
