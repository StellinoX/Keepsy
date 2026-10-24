import SwiftUI

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
    @State private var showSpecialCardLockModal = false
    @State private var specialCardFrontOpacity = 0.0
    @State private var isSpecialCardUnlocked = false
    @State private var shouldRevealSpecialCardAfterIntro = false
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
    private let specialCardWidth: CGFloat = 250
    private let specialCardHeight: CGFloat = 375
    @State private var scrollOffset: CGFloat = 0

    var pinY: CGFloat {
        showCloseButton ? 135 : 80
    }

    var defaultY: CGFloat {
        guard hasSpecialCard else { return pinY }
        return pinY + specialCardHeight + 60
    }

    var offsetY: CGFloat {
        let currentY = defaultY + scrollOffset
        let targetY = pinY
        return currentY < targetY ? targetY - currentY : 0
    }

    var headerTitle: String {
        if let loc = museumLocation, let museum = MuseumConfig.shared.museums.first(where: { $0.id == loc.lowercased() }) {
            return museum.name.uppercased()
        }
        return "GLOBAL COLLECTION"
    }

    var museumCity: String {
        guard let loc = museumLocation,
              let museum = MuseumConfig.shared.museums.first(where: { $0.id == loc.lowercased() })
        else { return "" }
        return museum.city
    }

    var collectionProgress: Double {
        guard !filteredArtworks.isEmpty else { return 0 }
        let foundCount = filteredArtworks.filter { revealedCards.contains($0) || foundCards.contains($0) }.count
        return Double(foundCount) / Double(filteredArtworks.count)
    }

    var filteredArtworks: [String] {
        if let loc = museumLocation {
            return CardDatabase.artworksFor(location: loc)
        }
        return CardDatabase.allArtworkNames
    }

    var isCollectionComplete: Bool {
        guard !filteredArtworks.isEmpty else { return false }
        return filteredArtworks.allSatisfy { revealedCards.contains($0) || foundCards.contains($0) }
    }

    private var hasSpecialCard: Bool {
        guard let location = museumLocation?.lowercased() else { return false }
        return location == "moma" || location == "prado" || location == "uffizi"
    }

    var experienceCardName: String {
        switch museumLocation?.lowercased() {
        case "moma": "vale"
        case "prado": "prado_experience"
        default: "uffizi_experience"
        }
    }

    private var specialCardUnlockKey: String {
        "specialCardRevealed_\(museumLocation?.lowercased() ?? "global")"
    }

    var destinationFrame: CGRect {
        let sw = screenSize.width
        let sh = screenSize.height
        let w: CGFloat = min(sw - 48, 300)
        let h: CGFloat = w * (470.0 / 310.0)
        let sheetPeek: CGFloat = 160
        let cardTopY: CGFloat = max(135, (sh - h - sheetPeek) / 2 + 10)
        return CGRect(x: (sw - w) / 2, y: cardTopY, width: w, height: h)
    }
    
    var sheetWidth: CGFloat {
        screenSize.width > 0 ? min(screenSize.width - 24, 373) : 373
    }
    var body: some View {
        // GeometryReader cattura le dimensioni schermo — usate da tutte le animazioni
        GeometryReader { rootGeo in
        let _ = { if screenSize == .zero { DispatchQueue.main.async { screenSize = rootGeo.size } } }()
        ZStack(alignment: .topLeading) {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            GridBackground()
                .blur(radius: showSpecialCardLockModal ? 20 : 0)

            // ── BACKGROUND LAYER: EXPERIENCE CARD ────────────────────────
            VStack(spacing: 0) {
                // Spacer for the top navigation bar area
                Spacer().frame(height: showCloseButton ? 135 : 80)
                
                // ── EXPERIENCE CARD SECTION ──────────────────────────────
                ZStack {
                    SpecialCardLockedBackView(
                        cardName: experienceCardName,
                        width: specialCardWidth,
                        height: specialCardHeight,
                        cornerRadius: 24
                    )
                    .opacity(1 - specialCardFrontOpacity)

                    let goldBorder = LinearGradient(
                        colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"),
                                 Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    ArtworkCardFrontView(
                        name: experienceCardName,
                        title: CardDatabase.cleanedArtworkName(experienceCardName),
                        cardIndex: nil,
                        width: specialCardWidth,
                        height: specialCardHeight,
                        isRevealed: true,
                        goldBorder: goldBorder
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .opacity(specialCardFrontOpacity)
                }
                .frame(width: specialCardWidth, height: specialCardHeight)
                .opacity(animatingCardName == experienceCardName ? cellCardOpacity : 1.0)
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
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .opacity(hasSpecialCard ? 1 : 0)
            .blur(radius: showSpecialCardLockModal ? 20 : 0)
            .allowsHitTesting(hasSpecialCard && !showSpecialCardLockModal)
            
            // ── FOREGROUND LAYER: MAIN SCROLL VIEW (THE SHEET/MODAL) ─────
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer corresponding to the height of the Experience Card section
                        ZStack(alignment: .top) {
                            Color.clear
                                .frame(height: defaultY)
                                .id("specialCardRevealAnchor")
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onAppear {
                                                scrollOffset = geo.frame(in: .named("root")).minY
                                            }
                                            .onChange(of: geo.frame(in: .named("root")).minY) { _, newValue in
                                                scrollOffset = newValue
                                            }
                                    }
                                )
                                .allowsHitTesting(false)
                            
                            // Foreground interactive area for the Experience Card (both locked and unlocked)
                            Color.clear
                                .frame(width: specialCardWidth, height: specialCardHeight)
                                .contentShape(Rectangle())
                                .padding(.top, showCloseButton ? 135 : 80)
                                .onTapGesture {
                                    tapExperienceCard()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(isSpecialCardUnlocked ? "Experience card" : "Special card, locked")
                                .accessibilityHint(isSpecialCardUnlocked ? "Double-tap to open experience card" : "Complete collection to unlock")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHidden(!hasSpecialCard)
                                .allowsHitTesting(hasSpecialCard)
                        }
                        
                        // ── ALBUM GRID CONTAINER ─────────────────────────────────
                        ZStack(alignment: .top) {
                            // Pinned sheet background and grab handle
                            ZStack(alignment: .top) {
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
                                
                                // Grab handle (pill)
                                Capsule()
                                    .fill(Color(white: 0.28))
                                    .frame(width: 36, height: 5)
                                    .padding(.top, 10)
                                    .accessibilityHidden(true)
                            }
                            .shadow(color: Color.black.opacity(0.5), radius: 39, x: 0, y: 4)
                            .offset(y: offsetY)

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
                            .padding(.top, 110)
                            .padding(.bottom, 24)
                            .padding(.horizontal, 16)
                            .mask(
                                Rectangle()
                                    .padding(.top, offsetY + 110)
                            )

                            // Touch blocker for the header area to prevent tapping cards that have scrolled underneath it
                            Color.clear
                                .frame(height: 110)
                                .contentShape(Rectangle())
                                .onTapGesture {} // Consumes taps, preventing them from reaching cards underneath
                                .offset(y: offsetY)

                            // Header dentro lo sheet: anello progress + titolo museo + città.
                            // Si muove insieme allo sheet (stesso offsetY) e resta visibile
                            // sopra la grid.
                            HStack(alignment: .center, spacing: 0) {
                                // Progress ring 90%
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                                    Circle()
                                        .trim(from: 0, to: collectionProgress)
                                        .stroke(Color.white,
                                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(collectionProgress * 100))%")
                                        .font(.custom("Helvetica-BoldOblique", size: 11))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 44, height: 44)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(Int(collectionProgress * 100)) percent of collection revealed")
                                .accessibilityAddTraits(.isStaticText)

                                Spacer()

                                VStack(spacing: 2) {
                                    Text(headerTitle)
                                        .font(.custom("Helvetica-BoldOblique", size: 26))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                    Text(museumCity)
                                        .font(.system(size: 14, weight: .regular).italic())
                                        .foregroundStyle(.white.opacity(0.7))
                                }

                                Spacer()

                                // Bilancia il ring così il titolo resta centrato
                                Color.clear.frame(width: 44, height: 44)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 28)
                            .offset(y: offsetY)
                            .allowsHitTesting(false)
                        }
                        .frame(width: sheetWidth)
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
            .blur(radius: showSpecialCardLockModal ? 20 : 0)
            .allowsHitTesting(!showSpecialCardLockModal)

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
                    .foregroundStyle(.white)
                    .frame(width: 85, height: 44)
                    .background(
                        Capsule().fill(Color(hex: "383838"))
                    )
                }
                .position(x: 30 + 85/2, y: 83 + 44/2)
                .blur(radius: showSpecialCardLockModal ? 20 : 0)
                .allowsHitTesting(!showSpecialCardLockModal)
                .accessibilityHint("Returns to pack selection")
            }



            // Floating cards bar removed - cards now animate directly from the screen center
            
            // Flying card e overlay dentro lo stesso ZStack "root"
            // così .position usa le stesse coordinate del GeometryReader
            if animationPhase != .idle {
                // Sfondo scuro e sfocato
                ZStack {
                    Color.black.opacity(0.45 * overlayOpacity)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .opacity(overlayOpacity)
                }
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

            if showSpecialCardLockModal {
                specialCardLockModal
                    .zIndex(200)
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

            configureSpecialCardUnlockState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("KeepsyCardsDidChange"))) { _ in
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
        }
        .onChange(of: rootGeo.size) { _, newSize in
            screenSize = newSize
        }
        .onChange(of: isCollectionComplete) { _, _ in
            configureSpecialCardUnlockState()
        }
        .task {
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true
        }
        }
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
        if (name.contains("_experience") || name == "vale") && !isSpecialCardUnlocked {
            let finalW: CGFloat = destinationFrame.width
            let scale = flyingFrame.width / finalW

            SpecialCardLockedBackView(
                cardName: name,
                width: finalW,
                height: destinationFrame.height,
                cornerRadius: 24
            )
            .scaleEffect(scale, anchor: .center)
            .frame(width: flyingFrame.width, height: flyingFrame.height)
            .opacity(flyingOpacity)
            .position(x: flyingFrame.midX, y: flyingFrame.midY)
        } else {
            let isRevealed = CardDatabase.getRevealedCards().contains(name) || CardDatabase.getFoundCards().contains(name) || name.contains("_experience") || name == "vale"
            let index = CardDatabase.remoteArtworks[name]?.cardNumber ?? (filteredArtworks.firstIndex(of: name).map { $0 + 1 })
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
        
        if !isSpecialCardUnlocked {
            HapticManager.shared.triggerNotification(type: .warning)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showSpecialCardLockModal = true
            }
        } else {
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
    }

    private func configureSpecialCardUnlockState() {
        guard hasSpecialCard else { return }

        guard isCollectionComplete else {
            isSpecialCardUnlocked = false
            specialCardFrontOpacity = 0
            shouldRevealSpecialCardAfterIntro = false
            UserDefaults.standard.removeObject(forKey: specialCardUnlockKey)
            return
        }

        if UserDefaults.standard.bool(forKey: specialCardUnlockKey) {
            isSpecialCardUnlocked = true
            specialCardFrontOpacity = 1
            return
        }

        if recentlyCompletedPack.isEmpty {
            // Existing or cloud-synced completed collections should not be locked again.
            isSpecialCardUnlocked = true
            specialCardFrontOpacity = 1
            UserDefaults.standard.set(true, forKey: specialCardUnlockKey)
        } else {
            // Keep the card covered until every newly collected sticker reaches its slot.
            isSpecialCardUnlocked = false
            specialCardFrontOpacity = 0
            shouldRevealSpecialCardAfterIntro = true
        }
    }

    private func revealSpecialCardIfNeeded(proxy: ScrollViewProxy) {
        guard hasSpecialCard,
              isCollectionComplete,
              shouldRevealSpecialCardAfterIntro,
              !isSpecialCardUnlocked
        else { return }

        shouldRevealSpecialCardAfterIntro = false
        isSpecialCardUnlocked = true
        specialCardFrontOpacity = 0
        UserDefaults.standard.set(true, forKey: specialCardUnlockKey)

        withAnimation(.easeInOut(duration: 0.7)) {
            proxy.scrollTo("specialCardRevealAnchor", anchor: .top)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            HapticManager.shared.triggerNotification(type: .success)
            withAnimation(.easeInOut(duration: 1.2)) {
                specialCardFrontOpacity = 1
            }
        }
    }

    private var specialCardLockModal: some View {
        ZStack {
            // Semi-transparent dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSpecialCardLockModal = false
                    }
                }
                .transition(.opacity)
                .accessibilityHidden(true)

            // Dialog Card
            VStack(spacing: 28) {
                // Title
                Text("SPECIAL CARD LOCKED")
                    .font(.custom("Helvetica-BoldOblique", size: 26))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .minimumScaleFactor(0.8)
                
                // Description
                VStack(spacing: 6) {
                    Text("An exclusive reward awaits.")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("Complete the collection to reveal it.")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 16)
                
                // Keep Exploring Button
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSpecialCardLockModal = false
                    }
                }) {
                    Text("KEEP EXPLORING")
                        .font(.custom("Helvetica-BoldOblique", size: 15))
                        .foregroundStyle(.black)
                        .frame(width: 240, height: 50)
                        .background(
                            Capsule()
                                .fill(Color(hex: "D8D8D8"))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(width: 340)
            .padding(.vertical, 42)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "B1B1B1")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
            )
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 20)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
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

        flyingFrame = destinationFrame
        flyingCornerRadius = 18
        withAnimation(.easeInOut(duration: 0.15)) {
            inspectionOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.40)) {
                flyingFrame = pulledSourceFrame
                flyingCornerRadius = 8
                overlayOpacity = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                // ── Aggiorna i frame con la posizione attuale della cella ──
                if let name = animatingCardName,
                   let f = frameTracker.cellFrames[name] {
                    sourceFrame       = CGRect(x: f.minX + 7, y: f.minY + 5, width: 58,  height: 84)
                    pulledSourceFrame = CGRect(x: sourceFrame.minX, y: sourceFrame.minY - pullDistance,
                                              width: sourceFrame.width, height: sourceFrame.height)
                    pocketFrame       = CGRect(x: f.minX,     y: f.minY + 5, width: 72,  height: 94)
                }

                if pocketFrame == .zero {
                    flyingOpacity = 0
                    animatingCardName = nil
                    animationPhase = .idle
                    withAnimation(.easeIn(duration: 0.08)) {
                        cellCardOpacity = 1.0
                    }
                } else {
                    // Fase B: anima SOLO il frame (la volante scende mantenendo opacity 1.0)
                    // A fine animazione: swap atomico volante→cella, no crossfade, no doppia immagine
                    withAnimation(.easeIn(duration: 0.30)) {
                        flyingFrame = sourceFrame
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        var t2 = Transaction(animation: nil)
                        t2.disablesAnimations = true
                        withTransaction(t2) {
                            flyingOpacity = 0
                            cellCardOpacity = 1.0
                            animatingCardName = nil
                            animationPhase = .idle
                        }
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

            // Only now, after the final sticker is in its album slot, reveal the reward.
            revealSpecialCardIfNeeded(proxy: proxy)
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
            let finalPulledSourceFrame = CGRect(
                x: finalSourceFrame.minX,
                y: finalSourceFrame.minY - pullDistance,
                width: finalSourceFrame.width,
                height: finalSourceFrame.height
            )
            
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

            // Wait for the flight to finish, then reuse the same pocket-entry
            // motion used when a card is closed from its detail view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeIn(duration: 0.30)) {
                    flyingFrame = finalSourceFrame
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    HapticManager.shared.triggerImpact(style: .light)

                    // Swap the flying card with the card inside the pocket atomically.
                    // Keeping opacity at 1 during the descent avoids the old dissolve.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        animatedCompletedCards.insert(cardName)
                        cellCardOpacity = 1.0
                        flyingOpacity = 0.0
                        currentlyAnimatingSticker = nil
                        animatingCardName = nil
                        animationPhase = .idle
                    }

                    // Short pause, then repeat for the next sticker in the queue.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        animateNextSticker(index: index + 1, proxy: proxy)
                    }
                }
            }
        }
    }
    
    // placeNextStickerFromTop REMOVED - WE NOW USE THE HIGH-FIDELITY ANIMATENEXTSTICKER ZOOM INTRO NATIVELY!
}

private struct SpecialCardRevealView: View {
    let cardName: String
    let onDismiss: () -> Void

    @State private var backdropOpacity = 0.0
    @State private var cardScale = 0.55
    @State private var cardRotation = -10.0
    @State private var cardOpacity = 0.0
    @State private var glowOpacity = 0.0
    @State private var copyOpacity = 0.0

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(geometry.size.width - 64, 310)
            let cardHeight = cardWidth * (470.0 / 310.0)
            let goldBorder = LinearGradient(
                colors: [
                    Color(hex: "FFF4A8"),
                    Color(hex: "F1B40A"),
                    Color(hex: "8C6100"),
                    Color(hex: "F1B40A"),
                    Color(hex: "FFF4A8")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                Color.black
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color(hex: "F1B40A").opacity(0.34 * glowOpacity),
                        Color(hex: "FF7A00").opacity(0.10 * glowOpacity),
                        .clear
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: geometry.size.width * 0.8
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("COLLECTION COMPLETE")
                            .font(.custom("Helvetica-BoldOblique", size: 16))
                            .foregroundStyle(.white.opacity(0.8))

                        Text("SPECIAL CARD UNLOCKED")
                            .font(.custom("Helvetica-BoldOblique", size: 28))
                            .foregroundStyle(goldBorder)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                    }
                    .opacity(copyOpacity)

                    ArtworkCardFrontView(
                        name: cardName,
                        title: CardDatabase.cleanedArtworkName(cardName),
                        cardIndex: nil,
                        width: cardWidth,
                        height: cardHeight,
                        isRevealed: true,
                        goldBorder: goldBorder
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(goldBorder, lineWidth: 2)
                    }
                    .shadow(
                        color: Color(hex: "F1B40A").opacity(0.65 * glowOpacity),
                        radius: 38,
                        x: 0,
                        y: 12
                    )
                    .scaleEffect(cardScale)
                    .rotationEffect(.degrees(cardRotation))
                    .opacity(cardOpacity)

                    Button(action: onDismiss) {
                        Text("CONTINUE")
                            .font(.custom("Helvetica-BoldOblique", size: 15))
                            .foregroundStyle(.black)
                            .frame(maxWidth: 240)
                            .frame(height: 50)
                            .background(goldBorder, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(copyOpacity)
                    .accessibilityHint("Closes the special card reveal")
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task {
            withAnimation(.easeOut(duration: 0.3)) {
                backdropOpacity = 0.94
                glowOpacity = 1.0
            }

            try? await Task.sleep(for: .milliseconds(120))

            withAnimation(.spring(response: 0.75, dampingFraction: 0.68)) {
                cardScale = 1.0
                cardRotation = 0
                cardOpacity = 1.0
            }

            try? await Task.sleep(for: .milliseconds(420))

            withAnimation(.easeOut(duration: 0.3)) {
                copyOpacity = 1.0
            }
        }
    }
}
