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

    var destinationFrame: CGRect {
        let sw = screenSize.width
        let sh = screenSize.height
        let w: CGFloat = 250
        let h: CGFloat = 380
        return CGRect(x: (sw - w) / 2, y: (sh - h) / 2 - 80, width: w, height: h)
    }
    var body: some View {
        // GeometryReader cattura le dimensioni schermo — usate da tutte le animazioni
        GeometryReader { rootGeo in
        // ZStack con coordinateSpace nominato — sia il GeometryReader che .position usano questo
        ZStack(alignment: .topLeading) {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            GridBackground()

            VStack(spacing: 20) {
                if showCloseButton {
                    HStack {
                        Spacer()
                        Text(headerTitle)
                            .font(.system(.headline, design: .monospaced))
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.top, 83 + 12)
                } else {
                    Spacer().frame(height: 40)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 33)
                        .fill(Color(white: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 33).stroke(
                            LinearGradient(
                                colors: [Color(hex: "B1B1B1"), Color(hex: "B1B1B1").opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        ))
                        .shadow(color: Color.black.opacity(0.5), radius: 39, x: 0, y: 4)

                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 33))
                }
                .frame(width: 373)
                .padding(.bottom, 20)
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
            }

            // FLOATING CARDS BAR — album-sized cards floating at top during sticker intro
            if stickerIntroActive && !recentlyCompletedPack.isEmpty {
                VStack(spacing: 8) {
                    Text("NUOVE OPERE RIVELATE!")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .italic()
                        .foregroundColor(Color(hex: "FFD700"))
                        .shadow(color: .black, radius: 2)
                    
                    HStack(spacing: 12) {
                        ForEach(recentlyCompletedPack, id: \.self) { name in
                            let isCurrent = name == currentlyAnimatingSticker
                            let isAnimated = animatedCompletedCards.contains(name)
                            
                            GeometryReader { cardGeo in
                                VStack(spacing: 0) {
                                    ArtImageView(cardName: name, isRevealed: true)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 76)
                                        .cornerRadius(5)
                                        .padding(4)
                                }
                                .frame(width: 58, height: 84)
                                .background(CardDatabase.gradientFor(name: name))
                                .cornerRadius(8)
                                .overlay(
                                    Group {
                                        if isCurrent {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: "4CD964"), lineWidth: 2)
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(CardDatabase.borderGradientFor(name: name), lineWidth: 1)
                                        }
                                    }
                                )
                                .shadow(color: isCurrent ? Color(hex: "4CD964").opacity(0.6) : Color.black.opacity(0.3), radius: isCurrent ? 8 : 4)
                                .opacity(isAnimated ? 0.25 : (isCurrent ? 0.0 : 1.0))
                                .scaleEffect(isCurrent ? 0.8 : 1.0)
                                .onAppear {
                                    let frame = cardGeo.frame(in: .named("root"))
                                    frameTracker.floatingCardFrames[name] = frame
                                }

                            }
                            .frame(width: 58, height: 84)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.6))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    )
                }
                .padding(.horizontal, 20)
                .position(x: screenSize.width / 2, y: screenSize.height - 120)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
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
        let pad = dynamicPadding
        VStack(spacing: 0) {
            ArtImageView(cardName: name, isRevealed: true)
                .aspectRatio(contentMode: .fill)
                .frame(width: flyingFrame.width - pad * 2, height: flyingFrame.height - pad * 2)
                .cornerRadius(max(4, flyingCornerRadius - pad))
                .padding(pad)
        }
        .frame(width: flyingFrame.width, height: flyingFrame.height)
        .background(CardDatabase.gradientFor(name: name))
        .cornerRadius(flyingCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: flyingCornerRadius)
                .stroke(CardDatabase.borderGradientFor(name: name), lineWidth: 1.5)
        )
        .shadow(color: Color.white.opacity(0.3), radius: 10)
        .opacity(flyingOpacity)
        .position(x: flyingFrame.midX, y: flyingFrame.midY)  // stesso spazio "root"
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
        inspectionOpacity = 0
        pocketOverlayOpacity = 1.0   // la bustina copre la carta mentre esce

        HapticManager.shared.triggerImpact(style: .medium)

        // Fase 1: sale verso l'alto — la copertina bustina svanisce
        // quando la carta ha percorso abbastanza da non stare più sotto la plastica
        withAnimation(.easeOut(duration: 0.28)) {
            flyingFrame = pulledSourceFrame
        }
        // La bustina svanisce nella seconda metà del pull (carta già uscita)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeOut(duration: 0.14)) {
                pocketOverlayOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            startZoomAnimation()
        }
    }

    func startZoomAnimation() {
        animationPhase = .zooming

        // Fase 2: zoom al centro
        withAnimation(.easeInOut(duration: 0.40)) {
            flyingFrame = destinationFrame
            flyingCornerRadius = 18
            overlayOpacity = 0.78
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            // La flying card rimane dov'è come scheletro.
            // CardInspectionView appare sopra con un fade morbido — nessun salto visivo.
            animationPhase = .open
            withAnimation(.easeInOut(duration: 0.18)) {
                inspectionOpacity = 1.0
                // flyingOpacity resta 1 — la inspection la copre perfettamente
            }
        }
    }

    func startCloseAnimation() {
        guard animationPhase == .open else { return }
        animationPhase = .closing

        HapticManager.shared.triggerImpact(style: .light)

        // La flying card è già a destinationFrame con flyingOpacity = 1 sotto la inspection.
        // Fade out della inspection — la flying card riappare senza stacco.
        flyingFrame = destinationFrame
        flyingCornerRadius = 18
        withAnimation(.easeInOut(duration: 0.15)) {
            inspectionOpacity = 0
            // flyingOpacity già 1, nessun cambio
        }

        // Fase A parte dopo il crossfade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.40)) {
                flyingFrame = pulledSourceFrame
                flyingCornerRadius = 8
                overlayOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                // Fase B: scende nella bustina
                // La plastica sovrapposta viene attivata istantaneamente al 100% prima della discesa!
                pocketOverlayOpacity = 1.0
                withAnimation(.easeIn(duration: 0.28)) {
                    flyingFrame = sourceFrame
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    flyingOpacity = 0
                    pocketOverlayOpacity = 0
                    withAnimation(.easeIn(duration: 0.08)) {
                        cellCardOpacity = 1.0
                    }
                    animatingCardName = nil
                    animationPhase = .idle
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
            
            // Measured source position in the bottom bar
            let sourcePos = frameTracker.floatingCardFrames[cardName] ?? CGRect(
                x: screenSize.width / 2 - 29,
                y: screenSize.height - 120 + 20,
                width: 58,
                height: 84
            )
            
            // Synchronized activation: hide from top bar & show in flyingCardView at the exact same frame!
            currentlyAnimatingSticker = cardName
            animatingCardName = cardName
            animationPhase = .pulling
            cellCardOpacity = 0.0
            overlayOpacity = 0.0
            flyingFrame = sourcePos
            flyingCornerRadius = 8
            flyingOpacity = 1.0
            
            // Set the pocket overlay frame and make it static/visible instantly!
            pocketFrame = finalPocketFrame
            pocketOverlayOpacity = 1.0
            
            HapticManager.shared.triggerImpact(style: .medium)
            
            // Phase 2: Fly from top bar down to just above its grid cell slot
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                flyingFrame = finalPulledSourceFrame
            }
            
            // Wait 0.55 seconds for this flight to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                // Phase 3: Slide down inside the plastic pocket sleeve texture!
                // The pocket overlay is already perfectly static and visible on the cell slot, so the card slides behind it!
                withAnimation(.easeOut(duration: 0.35)) {
                    flyingFrame = finalSourceFrame // Card slides down into cell behind the static outline
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
                    VStack(spacing: 0) {
                        ArtImageView(cardName: name, isRevealed: isRevealed)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 76)
                            .cornerRadius(5)
                            .padding(4)
                    }
                    .frame(width: 58, height: 84)
                    .background(CardDatabase.gradientFor(name: name))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CardDatabase.borderGradientFor(name: name), lineWidth: 1))
                    .shadow(color: Color.white.opacity(0.35), radius: 6, x: 0, y: 0)
                    .opacity(cardOpacity)

                    Image("pocket_outline")
                        .resizable()
                        .frame(width: 72, height: 94)
                        .padding(.top, 5)
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

                        Image("pocket_outline")
                            .resizable()
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
        lhs.frameRefreshToken == rhs.frameRefreshToken
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(artworks.enumerated()), id: \.offset) { index, name in
                AlbumCardCell(
                    name: name,
                    index: index,
                    isFound: foundCards.contains(name) || recentlyCompletedPack.contains(name),
                    isRevealed: revealedCards.contains(name) && !recentlyCompletedPack.contains(name) ? true : animatedCompletedCards.contains(name),
                    hasSynced: hasSyncedWithCloud,
                    cardOpacity: (animatingCardName == name) ? cellCardOpacity : (recentlyCompletedPack.contains(name) && !animatedCompletedCards.contains(name) ? 0.0 : 1.0)
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
                    guard foundCards.contains(name), animationPhase == .idle else { return }
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

