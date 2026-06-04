import SwiftUI

enum CardAnimationPhase {
    case idle, pulling, zooming, open, closing
}

class FrameTracker {
    var cellFrames: [String: CGRect] = [:]
    var floatingCardFrames: [String: CGRect] = [:]
}

struct CollectionAlbumView: View {
    var museumLocation: String? = nil
    var showCloseButton: Bool = false
    var onClose: (() -> Void)? = nil

    let columns = [
        GridItem(.fixed(72), spacing: 18),
        GridItem(.fixed(72), spacing: 18),
        GridItem(.fixed(72), spacing: 18),
        GridItem(.fixed(72), spacing: 18)
    ]

    @State private var foundCards: Set<String> = []
    @State private var revealedCards: Set<String> = []
    @State private var hasSyncedWithCloud = false
    @State private var inspectedCard: ArtworkCard? = nil
    @State private var showExperienceCardModal = false
    @State private var experienceCardFrame: CGRect = .zero
    @Namespace private var albumNamespace
    
    // Sticker placement sequence states
    @State private var recentlyCompletedPack: [String] = []
    @State private var animatedCompletedCards: Set<String> = []
    @State private var currentlyAnimatingSticker: String? = nil
    @State private var frameTracker = FrameTracker()
    @State private var frameRefreshToken: Int = 0
    
    @State private var stickerIntroActive: Bool = false
    
    @State private var animatingCardName: String? = nil
    @State private var animationPhase: CardAnimationPhase = .idle

    // Tutti i frame in coordinate dello stesso coordinateSpace "root"
    @State private var sourceFrame: CGRect = .zero
    @State private var pulledSourceFrame: CGRect = .zero

    // Flying card
    @State private var flyingFrame: CGRect = .zero
    @State private var flyingCornerRadius: CGFloat = 8
    @State private var flyingOpacity: Double = 0
    @State private var cellCardOpacity: Double = 1.0
    @State private var overlayOpacity: Double = 0
    @State private var inspectionOpacity: Double = 0

    // Frame del pocket_outline della cella sorgente (coordinate "root")
    // usato per sovrapporre la copertina durante pull/drop
    @State private var pocketFrame: CGRect = .zero
    @State private var pocketOverlayOpacity: Double = 0
    @State private var hideCellPocket: Bool = false   // true only during final descent (phase B)

    // Screen size captured from GeometryReader — available to animation functions
    @State private var screenSize: CGSize = .zero

    let pullDistance: CGFloat = 120

    var headerTitle: String {
        if let loc = museumLocation, let museum = MuseumConfig.shared.museums.first(where: { $0.id == loc.lowercased() }) {
            return museum.name.uppercased()
        }
        return "GLOBAL COLLECTION"
    }

    var filteredArtworks: [String] {
        if let loc = museumLocation {
            return CardDatabase.artworksFor(location: loc)
        }
        return CardDatabase.allArtworkNames
    }

    var isCollectionComplete: Bool {
        guard !filteredArtworks.isEmpty else { return false }
        return filteredArtworks.allSatisfy { revealedCards.contains($0) }
    }

    var experienceCardName: String {
        let loc = (museumLocation ?? "capodimonte").lowercased()
        return "\(loc)_experience"
    }

    var destinationFrame: CGRect {
        let sw = screenSize.width
        let sh = screenSize.height
        let w: CGFloat = min(sw - 48, 300)
        let h: CGFloat = w * (470.0 / 310.0)
        let sheetPeek: CGFloat = 160
        let cardTopY: CGFloat = max(140, (sh - h - sheetPeek) / 2 + 10)
        return CGRect(x: (sw - w) / 2, y: cardTopY, width: w, height: h)
    }
    var body: some View {
        // GeometryReader cattura le dimensioni schermo — usate da tutte le animazioni
        GeometryReader { rootGeo in
        let _ = { if screenSize == .zero { DispatchQueue.main.async { screenSize = rootGeo.size } } }()
        ZStack(alignment: .topLeading) {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            GridBackground()

            // ── BACKGROUND LAYER: EXPERIENCE CARD ────────────────────────
            VStack(spacing: 0) {
                // Spacer for the top navigation bar area
                Spacer().frame(height: showCloseButton ? 140 : 80)
                
                // ── EXPERIENCE CARD SECTION ──────────────────────────────
                VStack(spacing: 12) {
                    if isCollectionComplete {
                        let goldBorder = LinearGradient(
                            colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"),
                                     Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        ArtworkCardFrontView(
                            name: experienceCardName,
                            title: CardDatabase.cleanedArtworkName(experienceCardName),
                            cardIndex: nil,
                            width: 180,
                            height: 270,
                            isRevealed: true,
                            goldBorder: goldBorder
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .opacity(animatingCardName == experienceCardName ? cellCardOpacity : 1.0)
                        .shadow(color: Color(hex: "F1B40A").opacity(0.4), radius: 25, x: 0, y: 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        experienceCardFrame = geo.frame(in: .named("root"))
                                    }
                                    .onChange(of: geo.frame(in: .named("root"))) { _, newFrame in
                                        experienceCardFrame = newFrame
                                    }
                            }
                        )
                        .onTapGesture {
                            tapExperienceCard()
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "5168C4"), Color(hex: "3F53B3")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("?")
                                .font(.system(size: 80, weight: .black))
                                .foregroundColor(.white)
                        }
                        .frame(width: 180, height: 270)
                        .opacity(animatingCardName == experienceCardName ? cellCardOpacity : 1.0)
                        .shadow(color: Color(hex: "5168C4").opacity(0.4), radius: 25, x: 0, y: 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        experienceCardFrame = geo.frame(in: .named("root"))
                                    }
                                    .onChange(of: geo.frame(in: .named("root"))) { _, newFrame in
                                        experienceCardFrame = newFrame
                                    }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tapExperienceCard()
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // ── FOREGROUND LAYER: MAIN SCROLL VIEW (THE SHEET/MODAL) ─────
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer corresponding to the height of the Experience Card section
                        ZStack(alignment: .top) {
                            Color.clear
                                .frame(height: showCloseButton ? 470 : 410)
                                .allowsHitTesting(false)
                            
                            // Foreground interactive area for the Experience Card (both locked and unlocked)
                            Color.clear
                                .frame(width: 180, height: 270)
                                .contentShape(Rectangle())
                                .padding(.top, showCloseButton ? 140 : 80)
                                .onTapGesture {
                                    tapExperienceCard()
                                }
                        }
                        
                        // ── ALBUM GRID CONTAINER ─────────────────────────────────
                        ZStack {
                            RoundedRectangle(cornerRadius: 33)
                                .fill(Color(white: 0.12))
                                .overlay(RoundedRectangle(cornerRadius: 33).stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "B1B1B1"), Color(hex: "464646")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                ))
                                .shadow(color: Color.black.opacity(0.5), radius: 39, x: 0, y: 4)
                            
                            StickerGridView(
                                artworks: filteredArtworks,
                                foundCards: foundCards,
                                revealedCards: revealedCards,
                                recentlyCompletedPack: recentlyCompletedPack,
                                animatedCompletedCards: animatedCompletedCards,
                                hasSyncedWithCloud: hasSyncedWithCloud,
                                animatingCardName: animatingCardName,
                                cellCardOpacity: cellCardOpacity,
                                animationPhase: animationPhase,
                                hideCellPocket: hideCellPocket,
                                frameTracker: frameTracker,
                                frameRefreshToken: frameRefreshToken,
                                columns: columns
                            ) { name, f in
                                let figFrame = CGRect(x: f.minX + 7, y: f.minY + 5, width: 58, height: 84)
                                sourceFrame = figFrame
                                pocketFrame = CGRect(x: f.minX, y: f.minY + 5, width: 72, height: 94)
                                pulledSourceFrame = CGRect(x: figFrame.minX, y: figFrame.minY - pullDistance, width: figFrame.width, height: figFrame.height)
                                startPullAnimation(for: name)
                            }
                            .equatable()
                            .padding(.vertical, 24)
                            .padding(.horizontal, 16)
                        }
                        .frame(width: 373)
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    // Run the sticker intro after a short delay to allow views to render and frames to compile
                    if !recentlyCompletedPack.isEmpty {
                        runCompletedPackStickerIntro(proxy: proxy)
                    }
                }
                .onChange(of: stickerIntroActive) { _, newValue in
                    // Trigger sticker intro when data is loaded from outer onAppear
                    // (fixes race condition: inner onAppear fires before outer onAppear loads data)
                    if newValue && !recentlyCompletedPack.isEmpty {
                        runCompletedPackStickerIntro(proxy: proxy)
                    }
                }
            }

            if showCloseButton {
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    onClose?()
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

            // Floating cards bar removed - cards now animate directly from the screen center
            
            // Flying card e overlay dentro lo stesso ZStack "root"
            // così .position usa le stesse coordinate del GeometryReader
            if animationPhase != .idle {
                // Sfondo scuro
                Color.black
                    .opacity(overlayOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { startCloseAnimation() }

                // Flying card — posizionata con .position nello spazio "root"
                // Viene nascosta quando la CardInspectionView interattiva è aperta (.open) per evitare doppioni
                if let name = animatingCardName, animationPhase != .idle {
                    flyingCardView(for: name)
                        .id(name)
                        .opacity(animationPhase == .open ? max(0, 1.0 - inspectionOpacity) : 1.0)
                }

                // Copertina bustina sovrapposta alla flying card durante pull/drop
                // così la carta sembra uscire/rientrare da dentro la plastica
                Image("pocket_outline")
                    .resizable()
                    .frame(width: pocketFrame.width, height: pocketFrame.height)
                    .opacity(pocketOverlayOpacity)
                    .position(x: pocketFrame.midX, y: pocketFrame.midY)
                    .allowsHitTesting(false)

                // CardInspectionView — appare sopra la flying card con crossfade
                // La flying card resta visibile sotto come scheletro per evitare il salto
                if let name = animatingCardName, animationPhase == .open || animationPhase == .closing {
                    CardInspectionView(
                        card: ArtworkCard(
                            name: name,
                            imageName: name,
                            gradient: CardDatabase.gradientFor(name: name),
                            isFlipped: true
                        ),
                        namespace: albumNamespace,
                        isZoomingFromAlbum: true,
                        onClose: { startCloseAnimation() }
                    )
                    .id(name)
                    .opacity(inspectionOpacity)
                }
            }


        }
        // Nome del coordinateSpace — sia GeometryReader che .position lo usano
        .coordinateSpace(name: "root")
        .ignoresSafeArea()
        .onAppear {
            screenSize = rootGeo.size
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
            
            if let completed = UserDefaults.standard.stringArray(forKey: "recentlyCompletedPackCards"), !completed.isEmpty {
                recentlyCompletedPack = completed
                stickerIntroActive = true
            }
        }
        .onChange(of: rootGeo.size) { _, newSize in
            screenSize = newSize
        }
        .task {
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true
        }
        } // GeometryReader
        .ignoresSafeArea()
    }

    private var dynamicPadding: CGFloat {
        let minW: CGFloat = 58
        let maxW: CGFloat = 250
        let currentW = flyingFrame.width
        if currentW <= minW { return 4 }
        if currentW >= maxW { return 12 }
        let t = (currentW - minW) / (maxW - minW)
        return 4 + t * (12 - 4)
    }

    @ViewBuilder
    func flyingCardView(for name: String) -> some View {
        if name.contains("_experience") && !isCollectionComplete {
            let finalW: CGFloat = destinationFrame.width
            let finalH: CGFloat = destinationFrame.height
            let scale = flyingFrame.width / finalW
            
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "5168C4"), Color(hex: "3F53B3")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("?")
                    .font(.system(size: 80, weight: .black))
                    .foregroundColor(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .scaleEffect(scale, anchor: .center)
            .frame(width: flyingFrame.width, height: flyingFrame.height)
            .opacity(flyingOpacity)
            .position(x: flyingFrame.midX, y: flyingFrame.midY)
        } else {
            let isRevealed = CardDatabase.getRevealedCards().contains(name) || name.contains("_experience")
            let index = CardDatabase.allArtworkNames.firstIndex(of: name)
            let goldBorder = LinearGradient(
                colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"),
                         Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // La card finale è 300x457 — la scaliamo a qualsiasi dimensione con scaleEffect
            let finalW: CGFloat = destinationFrame.width
            let finalH: CGFloat = destinationFrame.height
            let scale = flyingFrame.width / finalW

            ArtworkCardFrontView(
                name: name,
                title: CardDatabase.cleanedArtworkName(name),
                cardIndex: index,
                width: finalW,
                height: finalH,
                isRevealed: isRevealed,
                goldBorder: goldBorder
            )
            .scaleEffect(scale, anchor: .center)
            .frame(width: flyingFrame.width, height: flyingFrame.height)
            .opacity(flyingOpacity)
            .position(x: flyingFrame.midX, y: flyingFrame.midY)
        }
    }

    private func tapExperienceCard() {
        guard recentlyCompletedPack.isEmpty else { return }
        guard animationPhase == .idle else { return }
        sourceFrame = experienceCardFrame
        pocketFrame = .zero
        pulledSourceFrame = experienceCardFrame
        
        animatingCardName = experienceCardName
        animationPhase = .zooming
        flyingFrame = experienceCardFrame
        flyingCornerRadius = 24
        flyingOpacity = 1.0
        overlayOpacity = 0.0
        cellCardOpacity = 0.0
        
        HapticManager.shared.triggerImpact(style: .medium)
        
        startZoomAnimation()
    }

    // MARK: - Animazioni

    func startPullAnimation(for name: String) {
        animatingCardName = name
        animationPhase = .pulling
        flyingFrame = sourceFrame       // parte esattamente dalla figurina
        flyingCornerRadius = 8
        flyingOpacity = 1.0
        cellCardOpacity = 0
        overlayOpacity = 0
        alignmentCheck()
        // The cell now always shows its own pocket_outline, so we don't need the
        // floating overlay on top during pull — it would create a double PNG.
        pocketOverlayOpacity = 0.0

        HapticManager.shared.triggerImpact(style: .medium)

        // Fase 1: sale verso l'alto
        withAnimation(.easeOut(duration: 0.28)) {
            flyingFrame = pulledSourceFrame
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            startZoomAnimation()
        }
    }

    private func alignmentCheck() {
        inspectionOpacity = 0
    }

    func startZoomAnimation() {
        animationPhase = .zooming

        withAnimation(.easeInOut(duration: 0.38)) {
            flyingFrame = destinationFrame
            flyingCornerRadius = 18
            overlayOpacity = 0.78
        }

        // Inizia il fade-in della inspection DOPO che lo zoom è finito (a 0.38s)
        // così la flying card ha raggiunto la destinazione e il crossfade è invisibile
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            animationPhase = .open
            withAnimation(.easeInOut(duration: 0.12)) {
                inspectionOpacity = 1.0
            }
        }
    }

    func startCloseAnimation() {
        guard animationPhase == .open else { return }
        animationPhase = .closing

        HapticManager.shared.triggerImpact(style: .light)

        // La flying card è sotto la inspection con opacity calcolata come (1 - inspectionOpacity).
        // Fade out inspection → flying card riappare automaticamente grazie alla formula nell'overlay.
        flyingFrame = destinationFrame
        flyingCornerRadius = 18
        withAnimation(.easeInOut(duration: 0.15)) {
            inspectionOpacity = 0
        }

        // Fase A parte dopo il crossfade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.40)) {
                flyingFrame = pulledSourceFrame
                flyingCornerRadius = 8
                overlayOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                if pocketFrame == .zero {
                    flyingOpacity = 0
                    animatingCardName = nil
                    animationPhase = .idle
                    withAnimation(.easeIn(duration: 0.08)) {
                        cellCardOpacity = 1.0
                    }
                } else {
                    // Fase B: scende nella bustina
                    // Nascondi il pocket della cella e attiva l'overlay prima della discesa
                    hideCellPocket = true
                    pocketOverlayOpacity = 1.0
                    withAnimation(.easeIn(duration: 0.28)) {
                        flyingFrame = sourceFrame
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        flyingOpacity = 0
                        pocketOverlayOpacity = 0
                        hideCellPocket = false
                        withAnimation(.easeIn(duration: 0.08)) {
                            cellCardOpacity = 1.0
                        }
                        animatingCardName = nil
                        animationPhase = .idle
                    }
                }
            }
        }
    }
    
    // MARK: - Sticker Insertion Intro Sequence
    
    func runCompletedPackStickerIntro(proxy: ScrollViewProxy) {
        guard !recentlyCompletedPack.isEmpty else { return }
        
        // Sort completed pack so stickers are placed in sequential album grid order
        recentlyCompletedPack = recentlyCompletedPack.sorted { a, b in
            let all = filteredArtworks
            return (all.firstIndex(of: a) ?? Int.max) < (all.firstIndex(of: b) ?? Int.max)
        }
        
        // Wait 1.0 second for the view to render before starting the premium reverse-zoom animation sequence!
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            animateNextSticker(index: 0, proxy: proxy)
        }
    }
    
    func animateNextSticker(index: Int, proxy: ScrollViewProxy) {
        guard index < recentlyCompletedPack.count else {
            // Finished animating all stickers! Clear local pack completed references
            withAnimation(.easeInOut(duration: 0.5)) {
                recentlyCompletedPack = []
                currentlyAnimatingSticker = nil
                animatingCardName = nil
                animationPhase = .idle
                flyingOpacity = 0.0
                pocketOverlayOpacity = 0.0
                cellCardOpacity = 1.0
                stickerIntroActive = false
            }
            UserDefaults.standard.removeObject(forKey: "recentlyCompletedPackCards")
            
            // Re-sync standard discovered cards state
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
            return
        }
        
        let cardName = recentlyCompletedPack[index]
        
        // 1. Scroll dynamically to center the target album cell in the ScrollView!
        HapticManager.shared.triggerSelection()
        withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
            proxy.scrollTo(cardName, anchor: .center)
        }
        
        // 2. Wait 0.7 seconds for scroll, then force-refresh all visible cell frames
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            frameRefreshToken += 1
        }
        
        // 3. Wait 0.9 seconds total for scroll + frame refresh to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let f = frameTracker.cellFrames[cardName] ?? CGRect(
                x: screenSize.width / 2 - 36,
                y: screenSize.height / 2 - 51,
                width: 72,
                height: 103
            )
            
            // Calculate corresponding frames matching Figma details tap mapping
            let finalSourceFrame = CGRect(x: f.minX + 7, y: f.minY + 5, width: 58, height: 84)
            let finalPocketFrame = CGRect(x: f.minX, y: f.minY + 5, width: 72, height: 94)
            let finalPulledSourceFrame = CGRect(x: finalSourceFrame.minX, y: finalSourceFrame.minY - 90, width: 58, height: 84) // Shifted up by 90pt so it starts completely outside/above the pocket slot!
            
            // Start the card flight from the center of the screen
            let sourcePos = CGRect(
                x: screenSize.width / 2 - 29,
                y: screenSize.height / 2 - 42,
                width: 58,
                height: 84
            )
            
            // Synchronized activation: hide from top bar & show in flyingCardView at the exact same frame!
            currentlyAnimatingSticker = cardName
            animatingCardName = cardName
            animationPhase = .pulling
            cellCardOpacity = 0.0
            overlayOpacity = 0.0
            hideCellPocket = false   // cella mostra il suo pocket durante il volo
            flyingFrame = sourcePos
            flyingCornerRadius = 8
            flyingOpacity = 1.0

            pocketFrame = finalPocketFrame
            pocketOverlayOpacity = 0.0

            HapticManager.shared.triggerImpact(style: .medium)

            // Phase 2: Fly from top bar down to just above its grid cell slot
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                flyingFrame = finalPulledSourceFrame
            }

            // Wait 0.55 seconds for this flight to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                // Phase 3: nascondi il pocket della cella e mostra l'overlay — così la carta scende "dentro"
                hideCellPocket = true
                pocketOverlayOpacity = 1.0
                withAnimation(.easeOut(duration: 0.35)) {
                    flyingFrame = finalSourceFrame
                }
                
                // Wait 0.35 seconds for card to completely slide inside
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    HapticManager.shared.triggerImpact(style: .light)
                    
                    // Add to animated set so the grid cell blinks and reveals
                    _ = withAnimation(.easeIn(duration: 0.15)) {
                        animatedCompletedCards.insert(cardName)
                    }
                    
                    // Hide flying overlays and reveal cell card
                    flyingOpacity = 0.0
                    pocketOverlayOpacity = 0.0
                    hideCellPocket = false
                    cellCardOpacity = 1.0
                    
                    // Reset animation states immediately for the current sticker!
                    // This completely destroys the flying view overlay, preventing it from holding onto the previous card's image state during the next scroll!
                    currentlyAnimatingSticker = nil
                    animatingCardName = nil
                    animationPhase = .idle
                    
                    // Short pause, then repeat for the next sticker in the queue!
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        animateNextSticker(index: index + 1, proxy: proxy)
                    }
                }
            }
        }
    }
    
    // placeNextStickerFromTop REMOVED - WE NOW USE THE HIGH-FIDELITY ANIMATENEXTSTICKER ZOOM INTRO NATIVELY!
}

// MARK: - AlbumCardCell

struct AlbumCardCell: View {
    let name: String
    let index: Int
    let isFound: Bool
    let isRevealed: Bool
    let hasSynced: Bool
    let cardOpacity: Double
    let isAnimating: Bool
    let hidePocket: Bool   // true only during final descent so flying card lands cleanly

    private var remoteURL: URL? {
        if let urlString = CardDatabase.remoteArtworks[name]?.imageUrl {
            return URL(string: urlString)
        }
        return nil
    }

    var body: some View {
        ZStack {
            if isFound {
                ZStack(alignment: .top) {
                    let borderGrad = CardDatabase.borderGradientFor(name: name)
                    ArtworkCardFrontView(
                        name: name,
                        title: CardDatabase.remoteArtworks[name]?.title ?? CardDatabase.cleanedArtworkName(name),
                        cardIndex: index,
                        width: 58,
                        height: 84,
                        isRevealed: isRevealed,
                        goldBorder: borderGrad
                    )
                    .opacity(cardOpacity)

                    // Hide pocket only during final descent (phase B) so the flying card
                    // lands cleanly. During pull-up and zoom the pocket stays visible.
                    if !(isAnimating && hidePocket) {
                        Image("pocket_outline")
                            .resizable()
                            .frame(width: 72, height: 94)
                            .padding(.top, 5)
                    }
                }
                .frame(width: 72, height: 103)

            } else {
                ZStack(alignment: .bottom) {
                    ZStack(alignment: .center) {
                        Text(String(format: "%03d", index + 1))
                            .font(.custom("Helvetica-BoldOblique", size: 17))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "000000"), Color(hex: "6F6F6F")],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
                            .padding(.top, 4)

                        if !isAnimating {
                            Image("pocket_outline")
                                .resizable()
                        }
                    }
                    .frame(width: 72, height: 94)
                }
                .frame(width: 72, height: 103, alignment: .bottom)
            }
        }
    }
}

// MARK: - Cell Frame Preference Key (replacement for per-cell GeometryReader)

struct CellFramePreference: Equatable {
    let name: String
    let frame: CGRect
}

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CellFramePreference] = []
    static func reduce(value: inout [CellFramePreference], nextValue: () -> [CellFramePreference]) {
        value.append(contentsOf: nextValue())
    }
}

struct StickerGridView: View, Equatable {
    let artworks: [String]
    let foundCards: Set<String>
    let revealedCards: Set<String>
    let recentlyCompletedPack: [String]
    let animatedCompletedCards: Set<String>
    let hasSyncedWithCloud: Bool
    let animatingCardName: String?
    let cellCardOpacity: Double
    let animationPhase: CardAnimationPhase
    let hideCellPocket: Bool
    let frameTracker: FrameTracker
    let frameRefreshToken: Int
    let columns: [GridItem]
    let onTapCard: (String, CGRect) -> Void

    static func == (lhs: StickerGridView, rhs: StickerGridView) -> Bool {
        lhs.artworks == rhs.artworks &&
        lhs.foundCards == rhs.foundCards &&
        lhs.revealedCards == rhs.revealedCards &&
        lhs.recentlyCompletedPack == rhs.recentlyCompletedPack &&
        lhs.animatedCompletedCards == rhs.animatedCompletedCards &&
        lhs.hasSyncedWithCloud == rhs.hasSyncedWithCloud &&
        lhs.animatingCardName == rhs.animatingCardName &&
        lhs.cellCardOpacity == rhs.cellCardOpacity &&
        lhs.animationPhase == rhs.animationPhase &&
        lhs.hideCellPocket == rhs.hideCellPocket &&
        lhs.frameRefreshToken == rhs.frameRefreshToken
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(artworks.enumerated()), id: \.offset) { index, name in
                AlbumCardCell(
                    name: name,
                    index: index,
                    isFound: revealedCards.contains(name) || recentlyCompletedPack.contains(name),
                    isRevealed: revealedCards.contains(name) && !recentlyCompletedPack.contains(name) ? true : animatedCompletedCards.contains(name),
                    hasSynced: hasSyncedWithCloud,
                    cardOpacity: (animatingCardName == name) ? cellCardOpacity : (recentlyCompletedPack.contains(name) && !animatedCompletedCards.contains(name) ? 0.0 : 1.0),
                    isAnimating: animatingCardName == name,
                    hidePocket: (animatingCardName == name) && hideCellPocket
                )
                .contentShape(Rectangle())
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CellFramePreferenceKey.self,
                            value: [CellFramePreference(name: name, frame: geo.frame(in: .named("root")))]
                        )
                    }
                )
                .onTapGesture {
                    guard recentlyCompletedPack.isEmpty else { return }
                    guard revealedCards.contains(name), animationPhase == .idle else { return }
                    if let f = frameTracker.cellFrames[name] {
                        onTapCard(name, f)
                    }
                }
                .frame(width: 72, height: 103)
                .id(name)
            }
        }
        .onPreferenceChange(CellFramePreferenceKey.self) { preferences in
            for pref in preferences {
                frameTracker.cellFrames[pref.name] = pref.frame
            }
        }
    }
}
