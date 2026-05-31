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
    
    // Triumph unlock animation states
    @State private var triggerUnlockAnimation: String? = nil
    @State private var foundCardName: String? = nil
    @State private var isAnimatingUnlock: Bool = false
    @State private var unlockStep: UnlockAnimationStep = .none

    enum UnlockAnimationStep {
        case none
        case zoomToCenter
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
            let safeTop = geometry.safeAreaInsets.top
            let cardWidth: CGFloat = screenWidth * 0.44
            let cardHeight: CGFloat = cardWidth * 1.5
            let cardCorner = cardWidth * 12.0 / 111.0

            ZStack {
                Color.black.ignoresSafeArea()

                // ── CAMERA ──────────────────────────────────────────────────
                if imagesReady {
                    ARViewContainer(
                        targetName: selectedTargetCard ?? "",
                        onArtworkDetected: { dbName in
                            let cleanedName = CardDatabase.cleanedArtworkName(dbName)
                            detectedArtwork = "Sbloccata: \(cleanedName)!"
                            isTargetUnlocked = true
                            if triggerUnlockAnimation == nil {
                                triggerUnlockAnimation = dbName
                            }
                        },
                        onWrongArtworkDetected: { dbName in
                            let cleanedTargetName = CardDatabase.cleanedArtworkName(selectedTargetCard ?? "")
                            detectedArtwork = "Non e' la carta selezionata! Trova \(cleanedTargetName)."
                        },
                        onDiagnosticMessageUpdated: { msg in
                            diagnosticMessage = msg
                        }
                    )
                    .ignoresSafeArea()
                } else {
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

                // ── ACTIVE PACK UI ───────────────────────────────────────────
                if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                    let displayCards = activePack.filter { $0 != foundCardName }

                    VStack(spacing: 0) {
                        // TOP PILL: back button left, artwork name centered
                        HStack(spacing: 0) {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .light)
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    activeView = .opening
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(width: 32, height: 32)
                            }

                            Spacer()

                            Text(isAnimatingUnlock ? "✨ OPERA TROVATA! ✨" : cleanedArtworkName(selectedTargetCard ?? ""))
                                .font(.system(size: 14, weight: .black))
                                .italic()
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            Color.clear.frame(width: 32, height: 32)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(isAnimatingUnlock ? Color(hex: "4CD964").opacity(0.85) : Color.black.opacity(0.65))
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, safeTop + 10)
                        .animation(.easeInOut(duration: 0.3), value: isAnimatingUnlock)

                        Spacer()

                        // CARD FAN
                        if !displayCards.isEmpty {
                            ZStack {
                                ForEach(Array(displayCards.enumerated()), id: \.element) { index, cardName in
                                    let isSelected = cardName == selectedTargetCard
                                    let selectedIndex = displayCards.firstIndex(of: selectedTargetCard ?? "") ?? 0
                                    let diff = CGFloat(index - selectedIndex)
                                    let xOffset = diff * cardWidth * 0.56
                                    let yOffset: CGFloat = abs(diff) * 18.0
                                    let rotation: Double = Double(diff) * 13.0
                                    let scale: CGFloat = isSelected ? 1.0 : 0.88

                                    ScannerCardView(name: cardName, width: cardWidth, height: cardHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: cardCorner)
                                                .stroke(
                                                    isSelected ? Color.white : Color(hex: "F1B40A").opacity(0.35),
                                                    lineWidth: isSelected ? 3 : 1.5
                                                )
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if duplicatesInPack.contains(cardName) || revealedCards.contains(cardName) {
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
                                        .shadow(color: isSelected ? .white.opacity(0.25) : .black.opacity(0.5), radius: isSelected ? 18 : 6)
                                        .rotationEffect(.degrees(rotation))
                                        .scaleEffect(scale)
                                        .offset(x: xOffset, y: yOffset)
                                        .zIndex(isSelected ? 10 : Double(5 - abs(Int(diff))))
                                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedTargetCard)
                                        .onTapGesture {
                                            guard !isAnimatingUnlock else { return }
                                            HapticManager.shared.triggerSelection()
                                            changeSelection(to: cardName)
                                        }
                                }
                            }
                            .frame(width: screenWidth, height: cardHeight + 80)
                            .background(Color.black.opacity(0.001))
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                    .onEnded { value in
                                        guard !isAnimatingUnlock else { return }
                                        if value.translation.width > 40 {
                                            HapticManager.shared.triggerSelection()
                                            selectPreviousCard(remainingCards: displayCards)
                                        } else if value.translation.width < -40 {
                                            HapticManager.shared.triggerSelection()
                                            selectNextCard(remainingCards: displayCards)
                                        }
                                    }
                            )
                        } else {
                            Spacer().frame(height: cardHeight + 80)
                        }

                        // Server error manual fallback
                        let currentCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
                        let isImageAvailable = CardDatabase.downloadedArtworkNames(for: currentCity).contains(selectedTargetCard ?? "")
                        if !isTargetUnlocked && !isImageAvailable && !isAnimatingUnlock && !displayCards.isEmpty {
                            Button(action: {
                                HapticManager.shared.triggerImpact(style: .medium)
                                if let target = selectedTargetCard { triggerUnlockAnimation = target }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Errore server: Sblocca manualmente")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.red.opacity(0.8)))
                            }
                            .padding(.bottom, 6)
                        }

                        if CardDatabase.isActivePackAllDuplicates() {
                            Text("Tutte già nella collezione")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 8)
                        }

                        Color.clear.frame(height: 24)
                    }
                    .zIndex(50)
                }

                // ── UNLOCK REVEAL LAYER ──────────────────────────────────────
                if isAnimatingUnlock, let name = foundCardName {
                    let revealCardWidth: CGFloat = screenWidth * 0.58
                    let revealCardHeight: CGFloat = revealCardWidth * 1.5
                    let revealCorner = revealCardWidth * 12.0 / 111.0

                    if unlockStep == .zoomToCenter {
                        let bgCards = (CardDatabase.getActivePack() ?? []).filter { $0 != name }
                        ZStack {
                            Color.black.opacity(0.6).ignoresSafeArea()
                            HStack(spacing: -40) {
                                ForEach(bgCards.prefix(4), id: \.self) { bgCard in
                                    ScannerCardView(name: bgCard, width: 130, height: 195)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 130 * 12.0 / 111.0)
                                                .stroke(Color(hex: "F1B40A").opacity(0.4), lineWidth: 1.5)
                                        )
                                        .blur(radius: 8)
                                        .opacity(0.5)
                                }
                            }
                            .frame(width: screenWidth)
                        }
                        .ignoresSafeArea()
                        .transition(.opacity)
                    }

                    VStack(spacing: 20) {
                        ScannerCardView(name: name, width: revealCardWidth, height: revealCardHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: revealCorner)
                                    .stroke(Color(hex: "4CD964"), lineWidth: 4)
                            )
                            .overlay(alignment: .topTrailing) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "4CD964"))
                                        .frame(width: 44, height: 44)
                                        .shadow(color: Color(hex: "4CD964").opacity(0.7), radius: 8)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 10, y: -10)
                            }
                            .shadow(color: Color(hex: "4CD964").opacity(0.7), radius: 28)

                        Text("CATTURATA!")
                            .font(.system(size: 20, weight: .black))
                            .italic()
                            .foregroundColor(.white)
                            .shadow(color: Color(hex: "4CD964").opacity(0.8), radius: 6)
                    }
                    .scaleEffect(unlockStep == .zoomToCenter ? 1.0 : 0.6)
                    .opacity(unlockStep == .zoomToCenter ? 1.0 : 0.0)
                    .position(x: screenWidth / 2, y: screenHeight / 2 - 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: unlockStep)
                    .zIndex(200)
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

                // Se TUTTE le carte sono già doppie: niente da inquadrare,
                // vai in automatico alla collezione dopo un breve momento.
                if CardDatabase.isActivePackAllDuplicates() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        navigateToCollection()
                    }
                }
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

    /// Pulisce il pacchetto attivo e naviga alla collezione.
    /// L'animazione "sticker che si inseriscono" parte da CollectionAlbumView
    /// leggendo recentlyCompletedPackCards (settato in startUnlockAnimation).
    private func navigateToCollection() {
        UserDefaults.standard.removeObject(forKey: "activePackCards")
        UserDefaults.standard.removeObject(forKey: "activePackTearMask")
        UserDefaults.standard.removeObject(forKey: "activePackDuplicates")
        let activeCity = UserDefaults.standard.string(forKey: "currentCity") ?? "capodimonte"
        withAnimation(.easeInOut(duration: 0.35)) {
            activeView = .collection(activeCity)
        }
    }
    
    private func changeSelection(to cardName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selectedTargetCard = cardName
            isTargetUnlocked = revealedCards.contains(cardName) || duplicatesInPack.contains(cardName)
            // Niente testo "già sbloccata": lo stato è comunicato dalla spunta verde sulla carta.
            detectedArtwork = isTargetUnlocked ? "" : "Trova l'opera per sbloccarla!"
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
        HapticManager.shared.triggerImpact(style: .rigid)

        foundCardName = cardName
        isAnimatingUnlock = true

        let activePackAtStart = CardDatabase.getActivePack() ?? []
        let dupes = CardDatabase.getDuplicatesInActivePack()
        let newCards = activePackAtStart.filter { !dupes.contains($0) }
        let isLastNewCard = newCards.filter { $0 != cardName }.allSatisfy { revealedCards.contains($0) }

        if isLastNewCard && !newCards.isEmpty {
            UserDefaults.standard.set(newCards, forKey: "recentlyCompletedPackCards")
        }

        CardDatabase.addRevealedCard(cardName)
        CardDatabase.clearActivePackIfNeeded()

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            unlockStep = .zoomToCenter
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                unlockStep = .none
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isAnimatingUnlock = false
                foundCardName = nil
                triggerUnlockAnimation = nil

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
                    navigateToCollection()
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
    let targetName: String
    let onArtworkDetected: @MainActor (String) -> Void
    let onWrongArtworkDetected: @MainActor (String) -> Void
    let onDiagnosticMessageUpdated: @MainActor (String) -> Void
    
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
        } else {
            targetArtworks = Array(downloaded.prefix(20))
        }
        
        guard !targetArtworks.isEmpty else {
            onDiagnosticMessageUpdated("Nessuna foto scaricata! (\(totalKnown) totali sul server). Apri prima la collezione.")
            arView.session.run(configuration)
            return arView
        }
        
        // Avvia la sessione vuota per non far laggare la UI all'apertura
        arView.session.run(configuration)
        
        // Carica immagini in background (await sospende il task liberando main thread),
        // poi configura e avvia la sessione AR sul main actor senza cross-actor send.
        Task(priority: .userInitiated) { @MainActor in
            var dynamicImages = Set<ARReferenceImage>()

            for name in targetArtworks {
                if let refImage = await CardDatabase.arReferenceImage(for: name) {
                    CardDatabase.validateARImage(refImage, name: name)
                    dynamicImages.insert(refImage)
                }
            }

            if !dynamicImages.isEmpty {
                configuration.trackingImages = dynamicImages
                configuration.maximumNumberOfTrackedImages = 1
                onDiagnosticMessageUpdated("✅ ARKit pronto: \(dynamicImages.count)/\(totalKnown) foto caricate.")
                arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            } else if let fallbackImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
                configuration.trackingImages = fallbackImages
                configuration.maximumNumberOfTrackedImages = 1
                onDiagnosticMessageUpdated("Uso \(fallbackImages.count) foto base da Xcode.")
                arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            } else {
                onDiagnosticMessageUpdated("❌ Nessuna foto trovata nel telefono!")
            }
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.targetName = targetName  // keep plain copy in sync (main thread)
    }
    
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARViewCoordinator) {
        uiView.session.pause()
    }
    
    func makeCoordinator() -> ARViewCoordinator {
        ARViewCoordinator(parent: self)
    }
}

// Private association key for targetName
nonisolated(unsafe) private var targetNameKey: UInt8 = 0

// MARK: - ARViewCoordinator: Standalone, thread-safe ARSCNView delegate
class ARViewCoordinator: NSObject, ARSCNViewDelegate {
    var parent: ARViewContainer
    
    weak var arView: ARSCNView?
    private let updateQueue = DispatchQueue(label: "ar.update.queue", qos: .userInitiated)

    init(parent: ARViewContainer) { 
        self.parent = parent
        super.init()
        self.targetName = parent.targetName
    }
    
    // Thread-safe targetName using atomic Objective-C Associated Objects
    nonisolated var targetName: String {
        get {
            objc_getAssociatedObject(self, &targetNameKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &targetNameKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
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

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }
        let rawName = imageAnchor.referenceImage.name ?? "Sconosciuta"
        // Read coordinator's plain-String copy (now synchronized via thread-safe lock getter)
        let capturedTargetName = targetName

        updateQueue.async {
            let dbName = rawName
            let foundCards = CardDatabase.getFoundCards()

            DispatchQueue.main.async {
                if capturedTargetName.isEmpty {
                    if foundCards.contains(dbName) {
                        self.parent.onArtworkDetected(dbName)
                    }
                } else if dbName == capturedTargetName {
                    self.parent.onArtworkDetected(dbName)
                } else {
                    self.parent.onWrongArtworkDetected(dbName)
                }
                self.parent.onDiagnosticMessageUpdated("Trovato: \(dbName)!")
            }
        }
    }
}
