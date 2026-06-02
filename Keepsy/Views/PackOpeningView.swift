import SwiftUI

struct LocationContainer: Identifiable {
    let id = UUID()
    let name: String
}

struct PackOpeningView: View {
    @Binding var activeView: ContentView.ActiveView
    @StateObject private var locationManager = LocationManager()
    @State private var packState: PackState = .selecting
    // Museum currently selected in the swipeable pack pager. Drives which museum's
    // cards a newly opened pack draws from. Persisted to the "currentCity" UserDefaults
    // key on open, which ARArtworkView reads for tracking + collection routing.
    @State private var selectedMuseumId: String = MuseumConfig.shared.museums.first?.id ?? "capodimonte"

    @State private var cards: [ArtworkCard] = []
    @State private var showCards = false
    @State private var packTearOffset: CGFloat = 0
    @State private var packOpacity: Double = 1.0
    @State private var inspectedCard: ArtworkCard? = nil
    @State private var hasSyncedWithCloud = false
    @State private var flashOpacity: Double = 0.0
    @State private var showOpeningEffect = false

    // Animazione carte — una per carta
    @State private var cardOffsetX: [CGFloat] = [123, 0, -123, 61.5, -61.5]
    @State private var cardOffsetY: [CGFloat] = [94, 94, 94, -94, -94]
    @State private var cardScale: [CGFloat] = Array(repeating: 1.0, count: 5)
    @State private var cardOpacity: [Double] = Array(repeating: 0, count: 5)
    @State private var cardRotation: [Double] = [-4, 2, -2, 3, 0]
    @State private var shimmerPhase: CGFloat = 0
    @State private var nextButtonScale: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            GridBackground()

            // Flash bianco all'apertura
            Color.white
                .edgesIgnoringSafeArea(.all)
                .opacity(flashOpacity)
                .blendMode(.screen)
                .allowsHitTesting(false)
                .zIndex(200)

            // Effetto apertura stile Pokemon Pocket
            if showOpeningEffect {
                PackOpeningFlashView {
                    showOpeningEffect = false
                }
                .zIndex(190)
                .allowsHitTesting(false)
            }

            if packState == .selecting {
                SingleScrollPackView(
                    currentCity: locationManager.currentCity,
                    selectedMuseumId: $selectedMuseumId,
                    onStart: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            packState = .tearing
                        }
                    },
                    onTapActivePack: {
                        onTapActivePack()
                    }
                )
            } else {
                ZStack {
                    if packState == .tearing || packState == .opened {
                        SceneKitPacketView(
                            onTearComplete: {
                                showOpeningEffect = true
                                withAnimation(.easeOut(duration: 0.06)) { flashOpacity = 1.0 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                    withAnimation(.easeIn(duration: 0.5)) { flashOpacity = 0.0 }
                                }
                            },
                            onOpen: {
                                completeOpening()
                            }
                        )
                        .ignoresSafeArea()
                        .opacity(packState == .opened ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: packState)
                        .zIndex(10)
                    }

                    if packState == .opened {
                        VStack {
                            Spacer()

                            ZStack {
                                VStack(spacing: 20) {
                                    // Riga 1: carte 0,1,2
                                    HStack(spacing: 12) {
                                        ForEach(0..<min(3, cards.count), id: \.self) { index in
                                            CardView(card: $cards[index], cardIndex: index) {
                                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                    inspectedCard = cards[index]
                                                }
                                            }
                                            .offset(x: cardOffsetX[index], y: cardOffsetY[index])
                                            .rotationEffect(.degrees(cardRotation[index]))
                                            .scaleEffect(cardScale[index])
                                            .opacity(cardOpacity[index])
                                        }
                                    }
                                    // Riga 2: carte 3,4
                                    if cards.count > 3 {
                                        HStack(spacing: 12) {
                                            ForEach(3..<min(5, cards.count), id: \.self) { index in
                                                CardView(card: $cards[index], cardIndex: index) {
                                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                        inspectedCard = cards[index]
                                                    }
                                                }
                                                .offset(x: cardOffsetX[index], y: cardOffsetY[index])
                                                .rotationEffect(.degrees(cardRotation[index]))
                                                .scaleEffect(cardScale[index])
                                                .opacity(cardOpacity[index])
                                            }
                                        }
                                    }
                                }

                                // Diagonal shimmer sweep after cards land
                                Rectangle()
                                    .fill(LinearGradient(
                                        colors: [.clear, .white.opacity(0.85), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: 40, height: 520)
                                    .rotationEffect(.degrees(-25))
                                    .offset(x: -260 + shimmerPhase * 700)
                                    .opacity(shimmerPhase > 0.001 ? 1 : 0)
                                    .blendMode(.overlay)
                                    .allowsHitTesting(false)
                            }

                            Spacer()
                            if cards.allSatisfy({ $0.isFlipped }) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        activeView = .arScanner
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        resetPack()
                                    }
                                }) {
                                    Text("NEXT")
                                        .font(.system(.headline, design: .monospaced))
                                        .bold()
                                        .foregroundColor(.black)
                                        .frame(width: 240, height: 50)
                                        .background(
                                            Capsule()
                                                .fill(LinearGradient(
                                                    colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00")],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ))
                                        )
                                        .shadow(color: Color(hex: "F1B40A").opacity(0.55), radius: 18, x: 0, y: 7)
                                }
                                .scaleEffect(nextButtonScale)
                                .onAppear {
                                    nextButtonScale = 0
                                    withAnimation(.spring(response: 0.52, dampingFraction: 0.62)) {
                                        nextButtonScale = 1.08
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            nextButtonScale = 1.0
                                        }
                                    }
                                }
                                .padding(.bottom, 60)
                            }
                        }
                        .zIndex(20)
                    }
                }
            }

            if packState == .opened && inspectedCard == nil {
                VStack {
                    HStack {
                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .light)
                            withAnimation(.easeInOut(duration: 0.35)) {
                                resetPack()
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
                        .padding(.top, 61)
                        .padding(.leading, 30)
                        
                        Spacer()
                    }
                    Spacer()
                }
                .ignoresSafeArea()
                .zIndex(150)
            }

            if let card = inspectedCard {
                CardInspectionView(card: card) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        self.inspectedCard = nil
                    }
                }
                .id(card.name)
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .task {
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true
        }
        .onChange(of: hasSyncedWithCloud) { _, synced in
            if synced && packState == .opened { loadActivePack() }
        }
        .onAppear {
            // Open the pager on the active pack's museum, if one is in progress.
            if CardDatabase.hasActivePack(),
               let activeMuseum = UserDefaults.standard.string(forKey: "currentCity") {
                selectedMuseumId = activeMuseum
            }
            loadActivePack()
        }
    }

    // MARK: - Animazione ingresso carte

    func animateCardsIn() {
        // Cards start at center-screen (offset counters their natural grid positions),
        // scaled down and randomly rotated — each bursts to its grid slot one by one.
        let startOffsets: [(x: CGFloat, y: CGFloat)] = [
            (123, 94), (0, 94), (-123, 94), (61.5, -94), (-61.5, -94)
        ]
        let startRotations: [Double] = [-38, 22, -30, 35, -18]

        for i in 0..<5 {
            cardOffsetX[i] = startOffsets[i].x
            cardOffsetY[i] = startOffsets[i].y
            cardScale[i] = 0.25
            cardOpacity[i] = 0
            cardRotation[i] = startRotations[i]
        }

        // Interleaved order: top-left, bottom-left, top-center, bottom-right, top-right
        let revealOrder: [Int] = [0, 3, 1, 4, 2]
        let stagger = 0.14
        let baseDelay = 0.12

        for seq in 0..<min(5, cards.count) {
            let i = revealOrder[seq]
            let delay = baseDelay + Double(seq) * stagger
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                HapticManager.shared.triggerImpact(style: seq == 0 ? .heavy : .medium)
                withAnimation(.spring(response: 0.46, dampingFraction: 0.6)) {
                    cardOffsetX[i] = 0
                    cardOffsetY[i] = 0
                    cardScale[i] = 1.08
                    cardOpacity[i] = 1.0
                    cardRotation[i] = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        cardScale[i] = 1.0
                    }
                }
            }
        }

        // Shimmer sweep starts after the last card settles
        let shimmerStart = baseDelay + Double(revealOrder.count - 1) * stagger + 0.46
        DispatchQueue.main.asyncAfter(deadline: .now() + shimmerStart) {
            withAnimation(.easeInOut(duration: 0.65)) {
                shimmerPhase = 1.0
            }
        }
    }

    // MARK: - Logic

    func completeOpening() {
        // Persist the opened museum so AR tracking + collection routing target it.
        UserDefaults.standard.set(selectedMuseumId, forKey: "currentCity")

        let artworks = CardDatabase.artworksFor(location: selectedMuseumId).shuffled()
        let selectedArtworks = Array(artworks.prefix(5))

        self.cards = selectedArtworks.map {
            ArtworkCard(
                name: $0,
                imageName: $0,
                gradient: CardDatabase.gradientFor(name: $0),
                isFlipped: false
            )
        }
        // Traccia doppie PRIMA di aggiungere a foundCards, altrimenti tutte risultano doppie.
        // Scrivi SEMPRE (anche vuoto) per non ereditare doppie stale dal pack precedente.
        let duplicates = CardDatabase.trackDuplicates(in: selectedArtworks)
        UserDefaults.standard.set(duplicates, forKey: "activePackDuplicates")

        CardDatabase.addFoundCards(selectedArtworks)
        UserDefaults.standard.set(selectedArtworks, forKey: "activePackCards")
        
        self.packState = .opened
        self.showCards = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.animateCardsIn()
        }
    }

    func loadActivePack() {
        if CardDatabase.hasActivePack() {
            let activeNames = CardDatabase.getActivePack() ?? []
            self.cards = activeNames.map { name in
                ArtworkCard(name: name, imageName: name, gradient: CardDatabase.gradientFor(name: name), isFlipped: true)
            }
            // Carte già viste: mostrale subito senza animazione
            for i in 0..<5 {
                cardOffsetX[i] = 0
                cardOffsetY[i] = 0
                cardScale[i] = 1.0
                cardOpacity[i] = 1.0
                cardRotation[i] = 0
            }
        } else {
            self.cards = []
        }
    }

    func onTapActivePack() {
        loadActivePack()
        packState = .opened
        showCards = true
    }

    func resetPack() {
        packState = .selecting
        showCards = false
        cards = []
        packTearOffset = 0
        packOpacity = 1.0
        inspectedCard = nil
        flashOpacity = 0.0
        showOpeningEffect = false
        shimmerPhase = 0
        nextButtonScale = 0

        cardOffsetX = [123, 0, -123, 61.5, -61.5]
        cardOffsetY = [94, 94, 94, -94, -94]
        cardScale = Array(repeating: 1.0, count: 5)
        cardOpacity = Array(repeating: 0, count: 5)
        cardRotation = [-4, 2, -2, 3, 0]
    }
}

// MARK: - SingleScrollPackView, PackExpansionRow, LightBeamView
// (invariati rispetto all'originale)

struct SingleScrollPackView: View {
    let currentCity: String
    @Binding var selectedMuseumId: String
    let onStart: () -> Void
    let onTapActivePack: () -> Void

    @State private var revealedCards: Set<String> = []
    @State private var activeLocation: LocationContainer? = nil
    @State private var savedTearMask: UIImage?

    private var museums: [Museum] { MuseumConfig.shared.museums }

    // The museum whose pack is currently opened (awaiting AR scan), if any.
    // Falls back to the first museum so a pack opened before museum separation
    // existed (no stored "currentCity") still surfaces instead of orphaning.
    private var activePackMuseum: String? {
        guard CardDatabase.hasActivePack() else { return nil }
        return UserDefaults.standard.string(forKey: "currentCity") ?? museums.first?.id
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                locationChip
                    .padding(.top, 105)
                    .padding(.bottom, 16)

                // Pacchetti divisi per museo — scorri orizzontalmente
                TabView(selection: $selectedMuseumId) {
                    ForEach(museums) { museum in
                        MuseumPackPage(
                            museum: museum,
                            isActiveMuseum: activePackMuseum == museum.id,
                            savedTearMask: savedTearMask,
                            revealedCards: revealedCards,
                            onTapActivePack: onTapActivePack
                        )
                        .tag(museum.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 440)

                // Indicatori pagina tra i pacchetti e il bottone
                if museums.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(museums) { museum in
                            Circle()
                                .fill(museum.id == selectedMuseumId ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 7, height: 7)
                                .animation(.easeInOut(duration: 0.2), value: selectedMuseumId)
                        }
                    }
                    .padding(.bottom, 14)
                }

                // Bottone statico: cambia stato in base al museo selezionato, non scorre
                let isSelectedActive = activePackMuseum == selectedMuseumId
                Button(action: isSelectedActive ? onTapActivePack : onStart) {
                    Text(isSelectedActive ? "VEDI CARTE" : "START")
                        .font(.system(size: 16, weight: .black)).italic()
                        .foregroundColor(.black)
                        .frame(width: isSelectedActive ? 160 : 134, height: 44)
                        .background(
                            Capsule()
                                .fill(isSelectedActive ? Color.orange : Color(hex: "D8D8D8"))
                                .shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4)
                        )
                }
                .padding(.bottom, 36)
                .animation(.easeInOut(duration: 0.2), value: selectedMuseumId)

                // Collezioni divise per museo
                VStack(spacing: 14) {
                    ForEach(museums) { museum in
                        let info = progressFor(museum.id)
                        PackExpansionRow(
                            title: museum.name,
                            progress: info.progress,
                            onTap: { activeLocation = LocationContainer(name: museum.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            revealedCards = CardDatabase.getRevealedCards()
            if let data = UserDefaults.standard.data(forKey: "activePackTearMask") {
                savedTearMask = UIImage(data: data)
            }
        }
        .fullScreenCover(item: $activeLocation) { container in
            CollectionAlbumView(museumLocation: container.name, showCloseButton: true) { activeLocation = nil }
        }
    }

    private var locationChip: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
                Image(systemName: "location.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(currentCity)
                .font(.system(size: 11, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .frame(width: 109, height: 30)
        .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    func progressFor(_ museumId: String) -> (progress: Double, found: Int, total: Int) {
        let artworks = CardDatabase.artworksFor(location: museumId)
        let found = artworks.filter { revealedCards.contains($0) }.count
        return (artworks.isEmpty ? 0 : Double(found) / Double(artworks.count), found, artworks.count)
    }
}

// MARK: - MuseumPackPage — una pagina del pager, il pacchetto di un singolo museo

struct MuseumPackPage: View {
    let museum: Museum
    let isActiveMuseum: Bool
    let savedTearMask: UIImage?
    let revealedCards: Set<String>
    let onTapActivePack: () -> Void

    private var activePack: [String]? {
        guard isActiveMuseum, let pack = CardDatabase.getActivePack(), !pack.isEmpty else { return nil }
        return pack
    }

    var body: some View {
        VStack(spacing: 0) {
            if let activePack = activePack {
                let firstCardName = activePack[0]
                SceneKitPacketView(interactive: false, isTorn: true, firstCardName: firstCardName,
                                   isFirstCardRevealed: revealedCards.contains(firstCardName),
                                   tearMaskImage: savedTearMask)
                    .frame(width: 290, height: 427)
                    .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                    .contentShape(Rectangle())
                    .onTapGesture { onTapActivePack() }
            } else {
                SceneKitPacketView(interactive: false)
                    .frame(width: 290, height: 427)
                    .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
            }
        }
        .padding(.top, 4)
    }
}

struct PackExpansionRow: View {
    let title: String
    let progress: Double
    let onTap: () -> Void
    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left side: Zoomed, fanned, and clipped packets
                ZStack {
                    SceneKitPacketView(interactive: false)
                        .frame(width: 140, height: 210)
                        .rotationEffect(.degrees(-9))
                        .offset(x: -18, y: 10)
                    
                    SceneKitPacketView(interactive: false)
                        .frame(width: 140, height: 210)
                        .rotationEffect(.degrees(9))
                        .offset(x: 18, y: 20)
                }
                .frame(width: 140, height: 194)
                .scaleEffect(1.2)
                .offset(x: 12, y: 10)
                
                Spacer()
                
                // Right side
                VStack(alignment: .trailing, spacing: 0) {
                    // Chevron at the top right
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 18)
                        .padding(.trailing, 20)
                    
                    Spacer()
                    
                    // Museum name (title) + percentage + progress bar in bottom right
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold)).italic()
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(percentText)
                            .font(.system(size: 28, weight: .black)).italic()
                            .foregroundColor(.white)
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 5)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(5, 110 * CGFloat(progress)), height: 5)
                        }
                        .frame(width: 110, height: 5)
                    }
                    .padding(.bottom, 22)
                    .padding(.trailing, 20)
                }
            }
            .frame(width: 344, height: 194)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "121214")) // Elegant premium dark background
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isComplete ?
                                    LinearGradient(colors: [Color(hex: "F2CA03"), Color(hex: "C7A245")], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color(hex: "B1B1B1"), Color(hex: "464646")], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16)) // Clip packets to card shape
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - PackOpeningFlashView — warm gold burst

struct PackOpeningFlashView: View {
    var onComplete: () -> Void

    @State private var burstScale: CGFloat = 0.1
    @State private var burstOpacity: Double = 0.0
    @State private var rayRotation: Double = 0
    @State private var rayOpacity: Double = 0.0
    @State private var rayScale: CGFloat = 0.3
    @State private var ring1Scale: CGFloat = 0.1
    @State private var ring1Opacity: Double = 0.0
    @State private var ring2Scale: CGFloat = 0.1
    @State private var ring2Opacity: Double = 0.0
    @State private var sparkOpacity: Double = 0.0
    @State private var sparkScale: CGFloat = 0.15
    @State private var globalOpacity: Double = 1.0

    private let goldColors: [Color] = [
        Color(hex: "F5E480"), Color(hex: "FFFFFF"),
        Color(hex: "F1B40A"), Color(hex: "FFD050"),
        Color(hex: "C8860A"), Color(hex: "FFFFFF"),
    ]

    var body: some View {
        ZStack {
            // 1. Central radial bloom — white core fading to warm gold
            RadialGradient(
                colors: [
                    Color.white.opacity(0.98),
                    Color(hex: "F5E480").opacity(0.9),
                    Color(hex: "F1B40A").opacity(0.55),
                    Color(hex: "9A6F00").opacity(0.25),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 310
            )
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .blendMode(.screen)

            // 2. Gold rays — static spokes, whole group rotates as one layer
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [
                                .clear,
                                goldColors[i % goldColors.count].opacity(0.52),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 2 + CGFloat(i % 4) * 1.5, height: 680)
                        .rotationEffect(.degrees(Double(i) * 30.0)) // static per-ray angle
                }
            }
            .drawingGroup() // rasterise to Metal texture once, then rotate that texture
            .rotationEffect(.degrees(rayRotation)) // single transform drives the spin
            .blur(radius: 1.0)
            .scaleEffect(rayScale)
            .opacity(rayOpacity)
            .blendMode(.screen)

            // 3. Inner ring — gold gradient expanding fast
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3.5
                )
                .frame(width: 190, height: 190)
                .scaleEffect(ring1Scale)
                .opacity(ring1Opacity)
                .blur(radius: 1.5)
                .blendMode(.screen)

            // 4. Outer ring — softer gold, slightly delayed
            Circle()
                .stroke(Color(hex: "F1B40A").opacity(0.45), lineWidth: 2)
                .frame(width: 290, height: 290)
                .scaleEffect(ring2Scale)
                .opacity(ring2Opacity)
                .blur(radius: 3)
                .blendMode(.screen)

            // 5. Ember sparks flying outward
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let size = CGFloat(4) + CGFloat(i % 4) * 2.5
                    let angle = Double(i) * (.pi * 2.0 / 16.0)
                    let radius = 145.0 * Double(sparkScale)
                    Circle()
                        .fill(goldColors[i % goldColors.count])
                        .frame(width: size, height: size)
                        .offset(x: CGFloat(cos(angle) * radius),
                                y: CGFloat(sin(angle) * radius))
                }
            }
            .drawingGroup()
            .blur(radius: 1.5)
            .opacity(sparkOpacity)
            .blendMode(.screen)
        }
        .opacity(globalOpacity)
        .ignoresSafeArea()
        .onAppear { runAnimation() }
    }

    func runAnimation() {
        withAnimation(.easeOut(duration: 0.22)) {
            burstScale = 2.3
            burstOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.14)) {
            rayOpacity = 1.0
            rayScale = 1.55
        }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            rayRotation = 360
        }
        withAnimation(.easeOut(duration: 0.38)) {
            ring1Scale = 4.0
            ring1Opacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.52).delay(0.08)) {
            ring2Scale = 3.2
            ring2Opacity = 0.8
        }
        withAnimation(.easeOut(duration: 0.36)) {
            sparkOpacity = 1.0
            sparkScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            withAnimation(.easeInOut(duration: 0.54)) {
                burstOpacity = 0
                rayOpacity = 0
                ring1Opacity = 0
                ring2Opacity = 0
                sparkOpacity = 0
                globalOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.54) {
                onComplete()
            }
        }
    }
}

struct PackOpeningView_Previews: PreviewProvider {
    static var previews: some View {
        PackOpeningView(activeView: .constant(.opening))
    }
}
