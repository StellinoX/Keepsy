import SwiftUI

enum CardAnimationPhase {
    case idle, pulling, zooming, open, closing
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
        let sw = UIScreen.main.bounds.width
        let sh = UIScreen.main.bounds.height
        let w: CGFloat = 260
        let h: CGFloat = w * (290.0 / 200.0)
        return CGRect(x: (sw - w) / 2, y: (sh - h) / 2, width: w, height: h)
    }
    var body: some View {
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

                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(Array(filteredArtworks.enumerated()), id: \.offset) { index, name in
                                GeometryReader { geo in
                                    AlbumCardCell(
                                        name: name,
                                        index: index,
                                        isFound: foundCards.contains(name),
                                        isRevealed: revealedCards.contains(name),
                                        hasSynced: hasSyncedWithCloud,
                                        cardOpacity: (animatingCardName == name) ? cellCardOpacity : 1.0
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        guard foundCards.contains(name),
                                              animationPhase == .idle else { return }
                                        // Legge il frame nel coordinateSpace "root" — stesso spazio di .position
                                        let f = geo.frame(in: .named("root"))
                                        let figFrame = CGRect(
                                            x: f.minX + 7,
                                            y: f.minY + 5,
                                            width: 58,
                                            height: 84
                                        )
                                        sourceFrame = figFrame
                                        // pocket_outline: 72×94 centrato nella cella 72×103, offset top 5
                                        pocketFrame = CGRect(
                                            x: f.minX,
                                            y: f.minY + 5,
                                            width: 72,
                                            height: 94
                                        )
                                        pulledSourceFrame = CGRect(
                                            x: figFrame.minX,
                                            y: figFrame.minY - pullDistance,
                                            width: figFrame.width,
                                            height: figFrame.height
                                        )
                                        startPullAnimation(for: name)
                                    }
                                }
                                .frame(width: 72, height: 103)
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
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

            // Flying card e overlay dentro lo stesso ZStack "root"
            // così .position usa le stesse coordinate del GeometryReader
            if animationPhase != .idle {
                // Sfondo scuro
                Color.black
                    .opacity(overlayOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { startCloseAnimation() }

                // Flying card — posizionata con .position nello spazio "root"
                if let name = animatingCardName {
                    flyingCardView(for: name)
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
                        namespace: Namespace().wrappedValue,
                        onClose: { startCloseAnimation() }
                    )
                    .opacity(inspectionOpacity)
                }
            }
        }
        // Nome del coordinateSpace — sia GeometryReader che .position lo usano
        .coordinateSpace(name: "root")
        .ignoresSafeArea()
        .onAppear {
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
        }
        .task {
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true
        }
    }

    @ViewBuilder
    func flyingCardView(for name: String) -> some View {
        VStack(spacing: 0) {
            ArtImageView(cardName: name, isRevealed: true)
                .aspectRatio(contentMode: .fill)
                .frame(width: flyingFrame.width - 8, height: flyingFrame.height - 8)
                .cornerRadius(max(4, flyingCornerRadius - 4))
                .padding(4)
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
                // La copertina riappare mentre la carta rientra sotto la plastica
                withAnimation(.easeIn(duration: 0.28)) {
                    flyingFrame = sourceFrame
                }
                // Bustina riappare nella seconda metà della discesa
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeIn(duration: 0.14)) {
                        pocketOverlayOpacity = 1.0
                    }
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
