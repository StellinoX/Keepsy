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
    
    // Triumph unlock animation states (Mockup 2)
    @State private var triggerUnlockAnimation: String? = nil
    @State private var foundCardName: String? = nil
    @State private var isAnimatingUnlock: Bool = false
    @State private var unlockStep: UnlockAnimationStep = .none
    
    // Collection icon feedback states (top-left collection glow/ripple)
    @State private var isCollectionIconVisible: Bool = false // Hidden by default, appears only when captured!
    @State private var collectionIconScale: CGFloat = 1.0
    @State private var isCollectionGlowActive: Bool = false
    @State private var collectionRippleScale: CGFloat = 1.0
    @State private var collectionRippleOpacity: Double = 0.0
    
    enum UnlockAnimationStep {
        case none
        case zoomToCenter      // Large center caught view with green glow border
        case flyToCollection   // Card flies and spins to the top-left collection icon
    }
    
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
                    // Camera feed showing AR tracking
                    ARViewContainer(
                        detectedArtwork: $detectedArtwork,
                        isTargetUnlocked: $isTargetUnlocked,
                        activeView: $activeView,
                        diagnosticMessage: $diagnosticMessage,
                        targetName: selectedTargetCard ?? "",
                        triggerUnlockAnimation: $triggerUnlockAnimation
                    )
                    .ignoresSafeArea()
                } else {
                    // Loading screen while images are downloaded
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
                
                // TOP BAR: Translucent back button & Collection binder shortcut
                HStack(spacing: 12) {
                    // 1. Chevron circular Back Button (permanently visible)
                    Button(action: {
                        HapticManager.shared.triggerImpact(style: .light)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            activeView = .opening
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    
                    // 2. Collection Album Indicator (Fades in dynamically only during triumph matching!)
                    ZStack {
                        // Golden/Glow background ring
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isCollectionGlowActive ? [Color(hex: "FFD700"), Color(hex: "FFA500")] : [Color(white: 0.15), Color(white: 0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: isCollectionGlowActive ? Color(hex: "FFD700").opacity(0.85) : .clear, radius: 12)
                            .scaleEffect(collectionIconScale)
                        
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isCollectionGlowActive ? .black : .white)
                        
                        // Expanding ripple circle when card hits
                        Circle()
                            .stroke(Color(hex: "FFD700"), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .scaleEffect(collectionRippleScale)
                            .opacity(collectionRippleOpacity)
                    }
                    .opacity(isCollectionIconVisible ? 1.0 : 0.0) // Appears only when matched!
                    .animation(.easeInOut(duration: 0.4), value: isCollectionIconVisible)
                }
                .padding(.top, 60)
                .padding(.leading, 24)
                .zIndex(100)
                
                // BOTTOM OVERLAY: Redesigned Large Fanned Cards Deck (Mockup 1)
                VStack(spacing: 12) {
                    Spacer()
                    
                    if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                        // Dynamic scan title
                        Text(isAnimatingUnlock ? "✨ OPERA TROVATA! ✨" : "TROVA: \(cleanedArtworkName(selectedTargetCard ?? ""))")
                            .font(.system(size: 14, weight: .black))
                            .italic()
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isAnimatingUnlock ? Color.green.opacity(0.8) : Color.black.opacity(0.6)))
                            .padding(.bottom, 6)
                        
                        // Point-to-scan diagnostic feedback
                        if !detectedArtwork.isEmpty && !isAnimatingUnlock {
                            Text(detectedArtwork)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                .padding(.bottom, 6)
                        }
                        
                        // Manual unlock fallback (server errors / simulator testing)
                        let currentCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                        let isImageAvailable = CardDatabase.downloadedArtworkNames(for: currentCity).contains(selectedTargetCard ?? "")
                        
                        if !isTargetUnlocked && !isImageAvailable && !isAnimatingUnlock {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                if let target = selectedTargetCard {
                                    triggerUnlockAnimation = target
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
                        
                        // LARGE PREMIUM FANNED CARD DECK (Mockup 1)
                        // Shows only unrevealed cards in current session, fanned out elegantly
                        let remainingCards = activePack.filter { cardName in
                            return !revealedCards.contains(cardName) && cardName != foundCardName
                        }
                        
                        if !remainingCards.isEmpty {
                            ZStack {
                                ForEach(Array(remainingCards.enumerated()), id: \.element) { index, cardName in
                                    let isSelected = cardName == selectedTargetCard
                                    let selectedIndex = remainingCards.firstIndex(of: selectedTargetCard ?? "") ?? 0
                                    let diff = CGFloat(index - selectedIndex)
                                    
                                    // Hearthstone fanning arithmetic (Larger cards to match Mockup 1)
                                    let cardRotation = diff * 11.0
                                    let xOffset = diff * 85.0      // Wider spacing to support larger size
                                    let yOffset = abs(diff) * 15.0 + (isSelected ? -25.0 : 0.0)
                                    let scale = isSelected ? 1.25 : 0.90
                                    
                                    VStack(spacing: 0) {
                                        ZStack(alignment: .topTrailing) {
                                            // Redesigned: Large cards matching mockup!
                                            let cardWidth: CGFloat = 130
                                            let cardHeight: CGFloat = 196
                                            let cornerRadius = cardWidth * 12.0 / 111.0
                                            
                                            ScannerCardView(
                                                name: cardName,
                                                width: cardWidth,
                                                height: cardHeight
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: cornerRadius)
                                                    .stroke(isSelected ? Color(hex: "F1B40A") : Color.white.opacity(0.35), lineWidth: isSelected ? 3 : 1.5)
                                            )
                                            .shadow(color: isSelected ? Color(hex: "F1B40A").opacity(0.5) : .black.opacity(0.4), radius: isSelected ? 16 : 6)
                                        }
                                    }
                                    .scaleEffect(scale)
                                    .rotationEffect(.degrees(cardRotation))
                                    .offset(x: xOffset, y: yOffset)
                                    .zIndex(isSelected ? 10 : Double(5 - abs(Int(diff))))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedTargetCard != cardName && !isAnimatingUnlock {
                                            HapticManager.shared.triggerSelection()
                                            changeSelection(to: cardName)
                                        }
                                    }
                                }
                            }
                            .frame(height: 260)
                            .contentShape(Rectangle())
                            // DRAG GESTURE: Enables smooth swiping left/right to scroll/navigate between cards in fanned hand!
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        guard !isAnimatingUnlock else { return }
                                        let dragDistance = value.translation.width
                                        if dragDistance > 45 {
                                            // Swipe Right -> Select Previous Card
                                            HapticManager.shared.triggerSelection()
                                            selectPreviousCard(remainingCards: remainingCards)
                                        } else if dragDistance < -45 {
                                            // Swipe Left -> Select Next Card
                                            HapticManager.shared.triggerSelection()
                                            selectNextCard(remainingCards: remainingCards)
                                        }
                                    }
                            )
                        } else {
                            Spacer().frame(height: 260)
                        }
                    } else {
                        // Diagnostic feedback if no active pack exists
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
                
                // TRIUMPH CATCH ANIMATION LAYER (Mockup 2 with bright green caught highlight)
                if isAnimatingUnlock, let name = foundCardName {
                    // Dark background overlay during Step 1 (isolating the card)
                    Color.black
                        .opacity(unlockStep == .zoomToCenter ? 0.75 : 0.0)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    // Shiny emerald green rotating rays behind the flying card (Step 1)
                    if unlockStep == .zoomToCenter {
                        RadialRayBeamView(color: Color(hex: "4CD964")) // Beautiful green rays!
                            .transition(.opacity)
                            .blendMode(.screen)
                            .position(x: screenWidth / 2, y: screenHeight / 2)
                    }
                    
                    // Large caught card (Mockup 2 size)
                    let cardWidth: CGFloat = 200
                    let cardHeight: CGFloat = 301
                    let cornerRadius = cardWidth * 12.0 / 111.0
                    
                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            ScannerCardView(
                                name: name,
                                width: cardWidth,
                                height: cardHeight
                            )
                            .overlay(
                                // Caught highlighted border: emerald green!
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .stroke(Color(hex: "4CD964"), lineWidth: 4)
                            )
                            // Bright emerald green glow!
                            .shadow(color: Color(hex: "4CD964").opacity(0.9), radius: 25)
                        }
                    }
                    .scaleEffect(unlockStep == .zoomToCenter ? 1.45 : 0.08)
                    .rotationEffect(.degrees(unlockStep == .zoomToCenter ? 0 : -360))
                    // Fly from screen center into the golden Collection Icon (x: 46+44, y: 60+22) in top-left!
                    .position(
                        x: unlockStep == .zoomToCenter ? screenWidth / 2 : 46.0 + 44.0,
                        y: unlockStep == .zoomToCenter ? screenHeight / 2 : 60.0 + 22.0
                    )
                    .animation(.spring(response: 0.84, dampingFraction: 0.76), value: unlockStep)
                }
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
        .onChange(of: triggerUnlockAnimation) { newValue in
            if let cardName = newValue {
                startUnlockAnimation(for: cardName)
            }
        }
    }
    
    func cleanedArtworkName(_ name: String) -> String {
        return CardDatabase.cleanedArtworkName(name)
    }
    
    private func changeSelection(to cardName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selectedTargetCard = cardName
            isTargetUnlocked = revealedCards.contains(cardName)
            detectedArtwork = isTargetUnlocked ? "Già sbloccata!" : "Trova l'opera per sbloccarla!"
        }
    }
    
    // Scrolling left / right between fanned card hand
    private func selectNextCard(remainingCards: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = remainingCards.firstIndex(of: current) else { return }
        if currentIndex < remainingCards.count - 1 {
            changeSelection(to: remainingCards[currentIndex + 1])
        }
    }
    
    private func selectPreviousCard(remainingCards: [String]) {
        guard let current = selectedTargetCard,
              let currentIndex = remainingCards.firstIndex(of: current) else { return }
        if currentIndex > 0 {
            changeSelection(to: remainingCards[currentIndex - 1])
        }
    }
    
    // Core game-like flying & green caught animation sequence (Mockup 2)
    private func startUnlockAnimation(for cardName: String) {
        // Step 1: Heavy spring bounce haptic
        HapticManager.shared.triggerImpact(style: .rigid)
        
        foundCardName = cardName
        isAnimatingUnlock = true
        isCollectionIconVisible = false // Ensure hidden first
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            unlockStep = .zoomToCenter
        }
        
        // Wait 1.4 seconds showing captured card with green border
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            // Step 2: Dynamically fade in the golden collection binder shortcut in top-left!
            withAnimation(.easeInOut(duration: 0.4)) {
                isCollectionIconVisible = true
            }
            
            // Wait 0.6 seconds more (making it 2.0s total celebration in center)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // Step 3: Card flies and spins to the Golden Album Icon in top-left
                withAnimation(.spring(response: 0.76, dampingFraction: 0.8)) {
                    unlockStep = .flyToCollection
                }
                
                // Wait 0.8 seconds (duration of flight)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    // Step 4: Hits the collection binder! Glow & spring bounce
                    HapticManager.shared.triggerImpact(style: .medium)
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                        collectionIconScale = 1.4
                        isCollectionGlowActive = true
                        collectionRippleScale = 1.0
                        collectionRippleOpacity = 1.0
                    }
                    
                    // expanding circular ring ripple wave
                    withAnimation(.easeOut(duration: 0.55)) {
                        collectionRippleScale = 2.4
                        collectionRippleOpacity = 0.0
                    }
                    
                    // Permanently save to revealed cards list
                    CardDatabase.addRevealedCard(cardName)
                    CardDatabase.clearActivePackIfNeeded()
                    
                    // Return golden collection icon size back to 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            collectionIconScale = 1.0
                        }
                    }
                    
                    // Wait another 0.6 seconds to let the user enjoy the ripple hit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCollectionGlowActive = false
                            isCollectionIconVisible = false // Fades out binder shortcut automatically!
                        }
                        
                        // Reset all animation states
                        isAnimatingUnlock = false
                        foundCardName = nil
                        unlockStep = .none
                        triggerUnlockAnimation = nil
                        
                        // Auto-select the next unrevealed card in fanned hand
                        if let active = CardDatabase.getActivePack(), !active.isEmpty {
                            let remaining = active.filter { !revealedCards.contains($0) }
                            if let nextTarget = remaining.first {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    selectedTargetCard = nextTarget
                                    isTargetUnlocked = false
                                    detectedArtwork = "Trova l'opera per sbloccarla!"
                                }
                            } else {
                                // All fanned cards found! Go back to pack opening view
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    activeView = .opening
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ScannerCardView: Mini Card View for Scanner Carousel (matching packet artwork card design)
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

// MARK: - RadialRayBeamView: Shiny gold/green rotating ray beams behind fanned cards
struct RadialRayBeamView: View {
    let color: Color
    @State private var rotation: Double = 0.0
    
    init(color: Color = Color(hex: "FFD700")) {
        self.color = color
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.6), color.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
            
            ForEach(0..<12, id: \.self) { i in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, color.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 8, height: 600)
                    .rotationEffect(.degrees(Double(i) * 30.0 + rotation))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
        }
    }
}

// MARK: - ARViewContainer: Dynamic multi-image target scanner pipeline
struct ARViewContainer: UIViewRepresentable {
    @Binding var detectedArtwork: String
    @Binding var isTargetUnlocked: Bool
    @Binding var activeView: ContentView.ActiveView
    @Binding var diagnosticMessage: String
    let targetName: String
    @Binding var triggerUnlockAnimation: String?
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        
        guard ARImageTrackingConfiguration.isSupported else {
            print("ARImageTrackingConfiguration is not supported on this device/simulator.")
            return arView
        }
        
        let configuration = ARImageTrackingConfiguration()
        var dynamicImages = Set<ARReferenceImage>()
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        let downloaded = CardDatabase.downloadedArtworkNames(for: activeCity)
        let totalKnown = CardDatabase.artworksFor(location: activeCity).count
        
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
                    let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: 0.2)
                    refImage.name = name
                    
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
        private let updateQueue = DispatchQueue(label: "ar.update.queue", qos: .userInitiated)

        init(parent: ARViewContainer) { self.parent = parent }

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            guard let imageAnchor = anchor as? ARImageAnchor else { return }
            let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"

            updateQueue.async {
                let dbName = rawName
                let cleanedName = CardDatabase.cleanedArtworkName(dbName)
                let targetName = self.parent.targetName
                let foundCards = CardDatabase.getFoundCards()

                DispatchQueue.main.async {
                    if targetName.isEmpty {
                        if foundCards.contains(dbName) {
                            if self.parent.triggerUnlockAnimation == nil {
                                self.parent.triggerUnlockAnimation = dbName
                                self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                                self.parent.isTargetUnlocked = true
                            }
                        }
                    } else if dbName == targetName {
                        // Pointed at target: trigger beautiful flight/unlock animation
                        if self.parent.triggerUnlockAnimation == nil {
                            self.parent.triggerUnlockAnimation = dbName
                            self.parent.detectedArtwork = "Sbloccata: \(cleanedName)!"
                            self.parent.isTargetUnlocked = true
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
