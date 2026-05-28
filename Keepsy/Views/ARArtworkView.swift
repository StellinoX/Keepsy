import SwiftUI
import ARKit
struct ARArtworkView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var detectedArtwork: String = ""
    @State private var isTargetUnlocked: Bool = false
    @State private var diagnosticMessage: String = "Avvio ARKit..."
    @State private var selectedTargetCard: String? = nil
    @GestureState private var gestureDragOffset: CGFloat = 0.0
    @State private var imagesReady: Bool = false
    @State private var downloadProgress: String = "Scaricamento immagini..."
    
    var revealedCards: Set<String> {
        return CardDatabase.getRevealedCards()
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                
                if imagesReady {
                    // Camera feed showing AR tracking (fullscreen as before)
                    ARViewContainer(
                        detectedArtwork: $detectedArtwork,
                        isTargetUnlocked: $isTargetUnlocked,
                        activeView: $activeView,
                        diagnosticMessage: $diagnosticMessage,
                        targetName: selectedTargetCard ?? ""
                    )
                    .ignoresSafeArea()
                } else {
                    // Loading screen while images are being downloaded
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text(downloadProgress)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
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
                            .padding(.bottom, 6)
                        
                        // Real-time detection feedback when pointing at something
                        if !detectedArtwork.isEmpty {
                            Text(detectedArtwork)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                .padding(.bottom, 6)
                        }
                        
                        // Check if the selected card's image is missing from server downloads
                        let currentCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                        let isImageAvailable = CardDatabase.downloadedArtworkNames(for: currentCity).contains(selectedTargetCard ?? "")
                        
                        if !isTargetUnlocked && !isImageAvailable {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                if let target = selectedTargetCard {
                                    CardDatabase.addRevealedCard(target)
                                    CardDatabase.clearActivePackIfNeeded()
                                    withAnimation {
                                        isTargetUnlocked = true
                                        detectedArtwork = "Sbloccata: \(cleanedArtworkName(target))!"
                                        if !CardDatabase.hasActivePack() {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                withAnimation(.easeInOut(duration: 0.35)) {
                                                    activeView = .opening
                                                }
                                            }
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Errore server: Sblocca manualmente")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.red.opacity(0.8)))
                                .padding(.bottom, 8)
                            }
                        }
                        
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
                        // Title/hint & Diagnostics
                        VStack {
                            Text(detectedArtwork.isEmpty ? "Cerca il quadro al muro" : detectedArtwork)
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                                .padding(.top, 50)
                            
                            Text(diagnosticMessage)
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }
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
        .task {
            // Ensure images are on disk before starting ARKit
            let city = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
            
            // Optimization: if we have an active pack, only wait for and download missing images of the active pack!
            // This reduces the loading screen delay from ~20 seconds to less than 1 second!
            let targetList: [String]
            if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                targetList = activePack
            } else {
                targetList = CardDatabase.artworksFor(location: city)
            }
            
            let downloaded = CardDatabase.downloadedArtworkNames(for: city)
            let missing = targetList.filter { !downloaded.contains($0) }
            
            if !missing.isEmpty {
                await MainActor.run {
                    downloadProgress = "Scaricamento \(missing.count) immagini..."
                }
                await CardDatabase.downloadImages(for: missing)
                await MainActor.run {
                    downloadProgress = "Pronto!"
                }
            }
            
            await MainActor.run {
                imagesReady = true
            }
        }
    }
    
    func cleanedArtworkName(_ name: String) -> String {
        return CardDatabase.cleanedArtworkName(name)
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
                ArtImageView(cardName: name)
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

struct ARViewContainer: UIViewRepresentable {
    @Binding var detectedArtwork: String
    @Binding var isTargetUnlocked: Bool
    @Binding var activeView: ContentView.ActiveView
    @Binding var diagnosticMessage: String
    let targetName: String
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        
        guard ARImageTrackingConfiguration.isSupported else {
            // Prevent crash on iOS Simulator
            print("ARImageTrackingConfiguration is not supported on this device/simulator.")
            return arView
        }
        
        let configuration = ARImageTrackingConfiguration()
        
        // Dynamically load reference images from downloaded server artworks
        var dynamicImages = Set<ARReferenceImage>()
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        let downloaded = CardDatabase.downloadedArtworkNames(for: activeCity)
        let totalKnown = CardDatabase.artworksFor(location: activeCity).count
        
        // Optimize reference images:
        // 1. If we have an active pack, ONLY track the cards in the active pack (max 5) that are downloaded!
        // This is extremely efficient, saves memory, and matches exactly what the user needs to find.
        // 2. If no active pack, limit to at most 20 downloaded images to prevent IOSurface/RAM starvation.
        var targetArtworks: [String] = []
        if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
            targetArtworks = activePack.filter { downloaded.contains($0) }
            print("ARKit tracking active pack cards: \(targetArtworks)")
        } else {
            targetArtworks = Array(downloaded.prefix(20))
            print("ARKit tracking first 20 downloaded cards: \(targetArtworks)")
        }
        
        guard !targetArtworks.isEmpty else {
            DispatchQueue.main.async {
                diagnosticMessage = "Nessuna foto scaricata! (\(totalKnown) totali sul server). Apri prima la collezione."
            }
            arView.session.run(configuration)
            return arView
        }
        
        for name in targetArtworks {
            autoreleasepool {
                if let cgImage = CardDatabase.rawCGImage(for: name) {
                    // We use a fallback width of 0.2 meters (20cm - typical for screen testing).
                    let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: 0.2)
                    refImage.name = name
                    
                    // Asynchronously validate the image to see if ARKit accepts it
                    refImage.validate { error in
                        if let error = error {
                            DispatchQueue.main.async {
                                diagnosticMessage = "Errore validazione: \(name) ha pochi dettagli."
                            }
                            print("ARKit Validation Error for \(name): \(error)")
                        }
                    }
                    
                    dynamicImages.insert(refImage)
                }
            }
        }
        
        if !dynamicImages.isEmpty {
            configuration.trackingImages = dynamicImages
            configuration.maximumNumberOfTrackedImages = 1
            DispatchQueue.main.async {
                diagnosticMessage = "✅ ARKit pronto: \(dynamicImages.count)/\(totalKnown) foto caricate."
            }
        } else if let fallbackImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
            // Fallback to Xcode Asset Catalog if no downloads exist yet
            configuration.trackingImages = fallbackImages
            configuration.maximumNumberOfTrackedImages = 1
            DispatchQueue.main.async {
                diagnosticMessage = "Uso \(fallbackImages.count) foto base da Xcode."
            }
        } else {
            DispatchQueue.main.async {
                diagnosticMessage = "❌ Nessuna foto trovata nel telefono!"
            }
        }
        
        arView.session.run(configuration)
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
    }
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        // Dedicated serial queue: prevents "retaining N ARFrames" warning
        private let updateQueue = DispatchQueue(label: "ar.update.queue", qos: .userInitiated)

        init(parent: ARViewContainer) { self.parent = parent }

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let imageAnchor = anchor as? ARImageAnchor else { return }
            // Capture the name immediately before leaving the render thread
            let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"

            updateQueue.async {
                let dbName = rawName
                let cleanedName = CardDatabase.cleanedArtworkName(dbName)
                let targetName = self.parent.targetName
                let foundCards = CardDatabase.getFoundCards()

                DispatchQueue.main.async {
                    if targetName.isEmpty {
                        if foundCards.contains(dbName) {
                            CardDatabase.addRevealedCard(dbName)
                            self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                            self.parent.isTargetUnlocked = true
                        }
                    } else if dbName == targetName {
                        CardDatabase.addRevealedCard(dbName)
                        CardDatabase.clearActivePackIfNeeded()
                        self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                        self.parent.isTargetUnlocked = true
                        if !CardDatabase.hasActivePack() {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    self.parent.activeView = .opening
                                }
                            }
                        }
                    } else {
                        let cleanedTargetName = CardDatabase.cleanedArtworkName(targetName)
                        self.parent.detectedArtwork = "Non e' la carta selezionata! Trova \(cleanedTargetName)."
                    }
                    self.parent.diagnosticMessage = "Trovato: \(dbName)!"
                }
            }
        }
    }
}
