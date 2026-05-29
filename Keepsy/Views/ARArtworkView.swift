import SwiftUI
import ARKit

struct ARArtworkView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var detectedArtwork: String = ""
    @State private var isTargetUnlocked: Bool = false
    @State private var diagnosticMessage: String = "Avvio ARKit..."
    @State private var selectedTargetCard: String? = nil

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
    
    var duplicatesInPack: Set<String> {
        return CardDatabase.getDuplicatesInActivePack()
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
                        
                        // CARD DECK — matching designer mockup layout
                        let displayCards = activePack.filter { $0 != foundCardName }
                        
                        if !displayCards.isEmpty {
                            ZStack {
                                ForEach(Array(displayCards.enumerated()), id: \.element) { index, cardName in
                                    let isSelected = cardName == selectedTargetCard
                                    let selectedIndex = displayCards.firstIndex(of: selectedTargetCard ?? "") ?? 0
                                    let diff = CGFloat(index - selectedIndex)
                                    
                                    // Designer layout: tight overlap, center card raised
                                    let xOffset = diff * 65.0
                                    let yOffset: CGFloat = isSelected ? 0.0 : 30.0
                                    let scale: CGFloat = isSelected ? 1.0 : 0.88
                                    
                                    let cardWidth: CGFloat = 160
                                    let cardHeight: CGFloat = 240
                                    let cornerRadius = cardWidth * 12.0 / 111.0
                                    
                                    ScannerCardView(
                                        name: cardName,
                                        width: cardWidth,
                                        height: cardHeight
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: cornerRadius)
                                            .stroke(Color(hex: "F1B40A").opacity(isSelected ? 1.0 : 0.55), lineWidth: isSelected ? 3.5 : 1.5)
                                    )
                                    // Overlay "doppia" — bollino verde con checkmark
                                    .overlay(alignment: .topTrailing) {
                                        if duplicatesInPack.contains(cardName) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "4CD964"))
                                                    .frame(width: 28, height: 28)
                                                    .shadow(color: Color(hex: "4CD964").opacity(0.6), radius: 4)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                    .shadow(color: isSelected ? Color(hex: "F1B40A").opacity(0.65) : .black.opacity(0.4), radius: isSelected ? 18 : 6)
                                    .scaleEffect(scale)
                                    .offset(x: xOffset, y: yOffset)
                                    .zIndex(isSelected ? 10 : Double(5 - abs(Int(diff))))
                                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedTargetCard)
                                    .onTapGesture {
                                        if !isAnimatingUnlock && !duplicatesInPack.contains(cardName) {
                                            HapticManager.shared.triggerSelection()
                                            changeSelection(to: cardName)
                                        }
                                    }
                                }
                            }
                            .frame(width: screenWidth, height: 300)
                            .clipped()
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 30)
                                    .onEnded { value in
                                        guard !isAnimatingUnlock else { return }
                                        let dragDistance = value.translation.width
                                        let swipeableCards = displayCards.filter { !duplicatesInPack.contains($0) }
                                        guard !swipeableCards.isEmpty else { return }
                                        if dragDistance > 40 {
                                            HapticManager.shared.triggerSelection()
                                            selectPreviousCard(remainingCards: swipeableCards)
                                        } else if dragDistance < -40 {
                                            HapticManager.shared.triggerSelection()
                                            selectNextCard(remainingCards: swipeableCards)
                                        }
                                    }
                            )
                        } else {
                            Spacer().frame(height: 320)
                        }
                        
                        // Se TUTTE le carte sono doppie, mostra pulsante per saltare AR
                        if CardDatabase.isActivePackAllDuplicates() {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                // Pulisci il pacchetto e torna alla collezione
                                UserDefaults.standard.removeObject(forKey: "activePackCards")
                                UserDefaults.standard.removeObject(forKey: "activePackTearMask")
                                UserDefaults.standard.removeObject(forKey: "activePackDuplicates")
                                let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    activeView = .collection(activeCity)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("TORNA ALLA COLLEZIONE")
                                        .font(.system(size: 14, weight: .black))
                                        .italic()
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                                .shadow(color: Color(hex: "FFD700").opacity(0.4), radius: 12)
                            }
                            .padding(.bottom, 20)
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
                // Seleziona la prima carta non-doppia come target iniziale
                let dupes = CardDatabase.getDuplicatesInActivePack()
                if let target = active.first(where: { !dupes.contains($0) }) {
                    selectedTargetCard = target
                } else {
                    // Tutte doppie — seleziona la prima comunque per il display
                    selectedTargetCard = active.first
                }
                isTargetUnlocked = dupes.contains(selectedTargetCard ?? "")
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
        .onChange(of: triggerUnlockAnimation) { _, newValue in
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
    
    private func startUnlockAnimation(for cardName: String) {
        // Step 1: Heavy spring bounce haptic
        HapticManager.shared.triggerImpact(style: .rigid)
        
        foundCardName = cardName
        isAnimatingUnlock = true
        isCollectionIconVisible = false // Ensure hidden first
        
        // 1. Pre-calculate active pack state at start to prevent clearing race conditions!
        let activePackAtStart = CardDatabase.getActivePack() ?? []
        let dupes = CardDatabase.getDuplicatesInActivePack()
        let newCards = activePackAtStart.filter { !dupes.contains($0) }
        let isLastNewCard = newCards.filter { $0 != cardName }.allSatisfy { revealedCards.contains($0) }
        
        if isLastNewCard && !newCards.isEmpty {
            // Solo carte nuove nel completedPack — le doppie non fanno sticker intro!
            let newlyRevealed = newCards.filter { !revealedCards.contains($0) || $0 == cardName }
            UserDefaults.standard.set(newlyRevealed, forKey: "recentlyCompletedPackCards")
            print("🎉 Pack completed! Saved recentlyCompletedPackCards (no dupes): \(newlyRevealed)")
        }
        
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
                        if !isLastNewCard {
                            if let active = CardDatabase.getActivePack(), !active.isEmpty {
                                let remaining = active.filter { !revealedCards.contains($0) && !dupes.contains($0) }
                                if let nextTarget = remaining.first {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        selectedTargetCard = nextTarget
                                        isTargetUnlocked = false
                                        detectedArtwork = "Trova l'opera per sbloccarla!"
                                    }
                                }
                            }
                        } else {
                            // All fanned cards found! Go directly to collection view to see the stickers insert
                            withAnimation(.easeInOut(duration: 0.35)) {
                                let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                                activeView = .collection(activeCity)
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
        context.coordinator.arView = arView
        
        // Pause session when resigning active to prevent background GPU access errors
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        // Resume session when becoming active
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        guard ARImageTrackingConfiguration.isSupported else {
            print("ARImageTrackingConfiguration is not supported on this device/simulator.")
            return arView
        }
        
        let configuration = ARImageTrackingConfiguration()
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        let downloaded = CardDatabase.downloadedArtworkNames(for: activeCity)
        let totalKnown = CardDatabase.artworksFor(location: activeCity).count
        
        var targetArtworks: [String] = []
        if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
            targetArtworks = activePack.filter { downloaded.contains($0) }
            // print("ARKit tracking active pack cards: \(targetArtworks)")
        } else {
            targetArtworks = Array(downloaded.prefix(20))
            // print("ARKit tracking first 20 downloaded cards: \(targetArtworks)")
        }
        
        guard !targetArtworks.isEmpty else {
            DispatchQueue.main.async {
                diagnosticMessage = "Nessuna foto scaricata! (\(totalKnown) totali sul server). Apri prima la collezione."
            }
            arView.session.run(configuration)
            return arView
        }
        
        // Avvia la sessione vuota per non far laggare la UI all'apertura
        arView.session.run(configuration)
        
        // Carica in background e poi aggiorna la configurazione
        Task.detached(priority: .userInitiated) {
            var dynamicImages = Set<ARReferenceImage>()
            
            for name in targetArtworks {
                if let refImage = await CardDatabase.arReferenceImage(for: name) {
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
            
            if !dynamicImages.isEmpty {
                configuration.trackingImages = dynamicImages
                configuration.maximumNumberOfTrackedImages = 1
                let loadedCount = dynamicImages.count
                await MainActor.run {
                    diagnosticMessage = "✅ ARKit pronto: \(loadedCount)/\(totalKnown) foto caricate."
                    arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                }
            } else if let fallbackImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
                configuration.trackingImages = fallbackImages
                configuration.maximumNumberOfTrackedImages = 1
                await MainActor.run {
                    diagnosticMessage = "Uso \(fallbackImages.count) foto base da Xcode."
                    arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                }
            } else {
                await MainActor.run {
                    diagnosticMessage = "❌ Nessuna foto trovata nel telefono!"
                }
            }
        }
        
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
        weak var arView: ARSCNView?
        private let updateQueue = DispatchQueue(label: "ar.update.queue", qos: .userInitiated)

        init(parent: ARViewContainer) { self.parent = parent }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func handleWillResignActive() {
            arView?.session.pause()
        }
        
        @objc func handleDidBecomeActive() {
            if let configuration = arView?.session.configuration {
                arView?.session.run(configuration)
            }
        }

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
