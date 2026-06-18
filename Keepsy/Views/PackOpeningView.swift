import SwiftUI

struct PackOpeningView: View {
    @Binding var activeView: ContentView.ActiveView
    @State private var locationManager = LocationManager()
    @State private var packState: PackState = .selecting
    // Museum currently selected in the swipeable packet pager. Drives which museum's
    // cards a newly opened pack draws from. Persisted to the "currentCity" UserDefaults
    // key on open, which ARArtworkView reads for tracking + collection routing.
    @State private var selectedMuseumId: String = MuseumConfig.shared.museums.first?.id ?? "capodimonte"
    @State private var showCitySelector = false

    @State private var cards: [ArtworkCard] = []
    @State private var showCards = false
    @State private var packTearOffset: CGFloat = 0
    @State private var packOpacity: Double = 1.0
    @State private var inspectedCard: ArtworkCard? = nil
    @State private var hasSyncedWithCloud = false
    @State private var pendingFlipIndex: Int? = nil
    @State private var flashOpacity: Double = 0.0
    @State private var showOpeningEffect = false
    @State private var shakeOffset: CGFloat = 0
    @State private var showTearHint = false
    @State private var packSwayX: CGFloat = 0
    @State private var showCompletionModal = false
    @State private var packRaised = false

    // Animazione carte — una per carta
    @State private var cardOffsetX: [CGFloat] = [123, 0, -123, -61.5, 61.5]
    @State private var cardOffsetY: [CGFloat] = [94, 94, 94, 94, 94]
    @State private var cardScale: [CGFloat] = Array(repeating: 1.0, count: 5)
    @State private var cardOpacity: [Double] = Array(repeating: 0, count: 5)
    @State private var cardRotation: [Double] = Array(repeating: 0, count: 5)
    @State private var shimmerPhase: CGFloat = 0
    @State private var nextButtonScale: CGFloat = 0
    @State private var isDealt = false

    // Pack del tearing estratto in una proprietà: viene montato sia in .packSelection
    // (pre-warm, nascosto dietro il rullo) sia in .tearing, mantenendo la STESSA identità
    // di view → la scena SceneKit non si re-inizializza e non c'è frame vuoto all'handoff.
    @ViewBuilder
    private var tearingPackView: some View {
        let scrW = UIScreen.mainBounds.width
        let scrH = UIScreen.mainBounds.height
        let pW = scrW * 0.90
        let pH = pW * (350.0 / 230.0)
        // Al SWAP (rullo → tearing) il pack DEVE essere identico al rullo: scale 2.0,
        // stessa posizione. Solo dopo, durante l'abbassamento, anima a restZoom.
        let raisedZoom: CGFloat = 2.0
        let restZoom:   CGFloat = 1.85
        let raisedY = scrH / 2 - scrH * 0.15
        let restY   = scrH / 2
        let lowered = (packState == .tearing && !packRaised)
        ZStack {
            SceneKitPacketView(
                museumId: selectedMuseumId,
                packetImageName: MuseumConfig.shared.museums.first(where: { $0.id == selectedMuseumId })?.packetImageName ?? "uffizi_pacchetto",
                raised: false,
                onTearComplete: {
                    showOpeningEffect = true
                    triggerShake()
                    withAnimation(.easeOut(duration: 0.02)) { flashOpacity = 0.8 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        withAnimation(.easeIn(duration: 0.28)) { flashOpacity = 0.0 }
                    }
                    SoundManager.shared.playSound(named: "san sebastiano")
                },
                onOpen: { completeOpening() }
            )
            .frame(width: pW, height: pH)
            .scaleEffect(lowered ? restZoom : raisedZoom)
            .shadow(color: Color(hex: "FF7A00").opacity(0.55), radius: 36, y: 18)
            .offset(x: packSwayX + shakeOffset)
            .position(x: scrW / 2, y: lowered ? restY : raisedY)

            if packState == .tearing && showTearHint && !showOpeningEffect && !packRaised {
                PackTearHintView(museumId: selectedMuseumId, packetZoom: lowered ? restZoom : raisedZoom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: scrW, height: scrH)
        .allowsHitTesting(packState == .tearing && !packRaised)
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                GridBackground()

                // Flash bianco all'apertura
                Color.white
                    .ignoresSafeArea()
                    .opacity(flashOpacity)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .zIndex(200)

                // Effetto apertura stile Pokemon Pocket
                PackOpeningFlashView(isTriggered: showOpeningEffect) {
                    showOpeningEffect = false
                }
                .zIndex(5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if packState == .selecting {
                    SingleScrollPackView(
                        activeView: $activeView,
                        currentCity: locationManager.currentCity,
                        selectedMuseumId: $selectedMuseumId,
                        onStart: {
                            if isMuseumComplete(selectedMuseumId) {
                                HapticManager.shared.triggerNotification(type: .warning)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    showCompletionModal = true
                                }
                            } else {
                                withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) {
                                    packState = .packSelection
                                }
                            }
                        },
                        onTapActivePack: {
                            onTapActivePack()
                        },
                        onTapCity: {
                            showCitySelector = true
                        }
                    )
                }

                // Pack del tearing montato GIÀ durante .packSelection, dietro il gradiente
                // opaco del rullo. La scena SceneKit è quindi già renderizzata: all'handoff
                // non compare il frame vuoto del primo render (niente sparizione).
                if packState == .packSelection || packState == .tearing {
                    tearingPackView
                        .zIndex(packState == .tearing ? 10 : 1)
                }

                if packState == .packSelection {
                    PackSelectionView(
                        museumId: selectedMuseumId,
                        onPacketSelected: {
                            packRaised = true
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) { packState = .tearing }
                            DispatchQueue.main.async {
                                withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                                    packRaised = false
                                }
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) {
                                packState = .selecting
                            }
                        }
                    )
                    .zIndex(5)
                    // Crossfade lungo all'uscita: maschera la differenza di render SceneKit
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: packState)
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
                                            handleCardTap(index: index)
                                        }
                                        .id(cards[index].id)
                                        .offset(x: cardOffsetX[index], y: cardOffsetY[index])
                                        .rotationEffect(.degrees(cardRotation[index]))
                                        .scaleEffect(cardScale[index])
                                        .opacity(cardOpacity[index])
                                        .allowsHitTesting(cardOpacity[index] > 0)
                                    }
                                }
                                // Riga 2: carte 3,4
                                HStack(spacing: 12) {
                                    ForEach(3..<min(5, cards.count), id: \.self) { index in
                                        CardView(card: $cards[index], cardIndex: index) {
                                            handleCardTap(index: index)
                                        }
                                        .id(cards[index].id)
                                        .offset(x: cardOffsetX[index], y: cardOffsetY[index])
                                        .rotationEffect(.degrees(cardRotation[index]))
                                        .scaleEffect(cardScale[index])
                                        .opacity(cardOpacity[index])
                                        .allowsHitTesting(cardOpacity[index] > 0)
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
                                .accessibilityHidden(true)
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
                                Text("KEEP'EM")
                                    .font(.custom("Helvetica-BoldOblique", size: 20))
                                    .foregroundStyle(.black)
                                    .frame(width: 232, height: 54)
                                    .background(
                                        RoundedRectangle(cornerRadius: 30)
                                            .fill(Color(hex: "D8D8D8"))
                                            .shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4)
                                    )
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
                            .accessibilityLabel("Keep cards")
                            .accessibilityHint("Saves all cards and opens AR scanner")
                        }
                    }
                    .zIndex(20)
                    .offset(x: shakeOffset)
                }

                if let card = inspectedCard {
                    CardInspectionView(card: card) {
                        self.inspectedCard = nil
                        if let i = self.pendingFlipIndex, i < self.cards.count {
                            self.cards[i].isFlipped = true
                            self.pendingFlipIndex = nil
                        }
                    }
                    .id(card.name)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .zIndex(100)
                }

                if packState == .opened && inspectedCard == nil {
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
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 85, height: 44)
                        .background(
                            Capsule().fill(Color(hex: "383838"))
                        )
                    }
                    .position(x: 30 + 85/2, y: 83 + 44/2)
                    .zIndex(150)
                    .accessibilityHint("Returns to pack selection")
                }
            } // Nested ZStack
            .blur(radius: showCompletionModal ? 20 : 0)
            .allowsHitTesting(!showCompletionModal)

            if showCompletionModal {
                completionModal
                    .zIndex(300)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showCitySelector) {
            CitySelectorView(selectedMuseumId: $selectedMuseumId)
        }
        .task {
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true
        }
        .onChange(of: hasSyncedWithCloud) { _, synced in
            if synced && packState == .opened && cards.isEmpty { loadActivePack() }
        }
        .onChange(of: packState) { _, newState in
            if newState == .tearing {
                showTearHint = false
                packSwayX = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    guard packState == .tearing, !showOpeningEffect else { return }
                    withAnimation(.easeIn(duration: 0.4)) { showTearHint = true }
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { showTearHint = false }
                packSwayX = 0
            }
        }
        .onChange(of: showOpeningEffect) { _, firing in
            if firing {
                withAnimation(.easeOut(duration: 0.15)) { showTearHint = false }
                packSwayX = 0
            }
        }
        .onChange(of: selectedMuseumId) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "lastSelectedMuseumId")
        }
        .onAppear {
            // Open the pager on the active pack's museum, if one is in progress.
            if CardDatabase.hasActivePack(),
               let activeMuseum = UserDefaults.standard.string(forKey: "currentCity") {
                selectedMuseumId = activeMuseum
            } else if let lastSelected = UserDefaults.standard.string(forKey: "lastSelectedMuseumId") {
                selectedMuseumId = lastSelected
            }
            loadActivePack()
        }
    }

    // MARK: - Card Tap Handler

    func handleCardTap(index: Int) {
        guard index < cards.count else { return }
        guard inspectedCard == nil else { return }

        if cards[index].isFlipped {
            // Già fronte: solo dettaglio, NIENTE suono
            withAnimation(.easeOut(duration: 0.25)) {
                inspectedCard = cards[index]
            }
        } else {
            // Retro: dettaglio (copia già girata). Girata applicata alla chiusura.
            var flipped = cards[index]
            flipped.isFlipped = true
            pendingFlipIndex = index
            withAnimation(.easeOut(duration: 0.25)) {
                inspectedCard = flipped
            }
        }
    }

    // MARK: - Shake

    func triggerShake() {
        let pattern: [(CGFloat, Double)] = [
            (-14, 0.00), (14, 0.055), (-10, 0.11), (10, 0.165),
            (-5, 0.22), (5, 0.275), (0, 0.33)
        ]
        for (offset, delay) in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = offset }
            }
        }
    }

    // MARK: - Animazione ingresso carte

    func animateCardsIn() {
        let finalRotations: [Double] = Array(repeating: 0, count: 5)

        cardOffsetX = [123, 0, -123, -61.5, 61.5]
        cardOffsetY = [94, 94, 94, 94, 94]
        cardScale = Array(repeating: 0.6, count: 5)
        cardOpacity = Array(repeating: 0, count: 5)
        cardRotation = finalRotations

        let revealOrder: [Int] = [0, 3, 1, 4, 2]
        let stagger = 0.14
        let baseDelay = 0.12

        for seq in 0..<min(5, cards.count) {
            let i = revealOrder[seq]
            let delay = baseDelay + Double(seq) * stagger
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                HapticManager.shared.triggerImpact(style: seq == 0 ? .heavy : .medium)
                withAnimation(.spring(response: 0.46, dampingFraction: 0.6)) {
                    var newOffsetsX = cardOffsetX
                    var newOffsetsY = cardOffsetY
                    var newScales = cardScale
                    var newOpacities = cardOpacity

                    if i < newOffsetsX.count { newOffsetsX[i] = 0 }
                    if i < newOffsetsY.count { newOffsetsY[i] = 0 }
                    if i < newScales.count { newScales[i] = 1.08 }
                    if i < newOpacities.count { newOpacities[i] = 1.0 }

                    cardOffsetX = newOffsetsX
                    cardOffsetY = newOffsetsY
                    cardScale = newScales
                    cardOpacity = newOpacities
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        var newScales = cardScale
                        if i < newScales.count { newScales[i] = 1.0 }
                        cardScale = newScales
                    }
                }
            }
        }

        let shimmerStart = baseDelay + Double(revealOrder.count - 1) * stagger + 0.46
        DispatchQueue.main.asyncAfter(deadline: .now() + shimmerStart) {
            withAnimation(.easeInOut(duration: 0.65)) {
                shimmerPhase = 1.0
            }
        }
    }

    // MARK: - Logic

    func completeOpening() {
        guard packState == .tearing else { return }
        UserDefaults.standard.set(selectedMuseumId, forKey: "currentCity")

        let revealed = CardDatabase.getRevealedCards()
        let artworks = CardDatabase.artworksFor(location: selectedMuseumId)

        // Escludi le carte già trovate/rivelate
        var remainingArtworks = artworks.filter { !revealed.contains($0) }

        // Se ci sono meno di 5 carte rimaste da trovare, riempi con le restanti già trovate
        if remainingArtworks.count < 5 {
            let needed = 5 - remainingArtworks.count
            let alreadyRevealed = artworks.filter { revealed.contains($0) }.shuffled()
            remainingArtworks.append(contentsOf: alreadyRevealed.prefix(needed))
        }

        var selectedArtworks = Array(remainingArtworks.shuffled().prefix(5))

        if selectedMuseumId == "capodimonte" {
            let flagellationKey = "14 - Caravaggio_Flagellazione di Cristo_Capodimonte_ph.L.Romano_10780"
            let found = CardDatabase.getFoundCards()
            if !revealed.contains(flagellationKey) && !found.contains(flagellationKey) {
                if !selectedArtworks.contains(flagellationKey) && !selectedArtworks.isEmpty {
                    selectedArtworks[selectedArtworks.count - 1] = flagellationKey
                }
            }
        }

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
        UserDefaults.standard.set(duplicates, forKey: "activePackDuplicates_\(selectedMuseumId)")

        CardDatabase.addFoundCards(selectedArtworks)
        UserDefaults.standard.set(selectedArtworks, forKey: "activePackCards_\(selectedMuseumId)")

        // Start background download for these specific 5 cards to ensure they are ready ASAP
        Task(priority: .userInitiated) {
            await CardDatabase.downloadImages(for: selectedArtworks)
        }

        cardOffsetX = [123, 0, -123, -61.5, 61.5]
        cardOffsetY = [94, 94, 94, 94, 94]
        cardScale = Array(repeating: 0.6, count: 5)
        cardOpacity = Array(repeating: 0, count: 5)
        cardRotation = Array(repeating: 0, count: 5)

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
            cardOffsetX = Array(repeating: 0, count: 5)
            cardOffsetY = Array(repeating: 0, count: 5)
            cardScale = Array(repeating: 1.0, count: 5)
            cardOpacity = Array(repeating: 1.0, count: 5)
            cardRotation = Array(repeating: 0, count: 5)
        } else {
            self.cards = []
        }
    }

    func onTapActivePack() {
        UserDefaults.standard.set(selectedMuseumId, forKey: "currentCity")
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
        shakeOffset = 0
        showTearHint = false
        packSwayX = 0
        shimmerPhase = 0
        nextButtonScale = 0

        cardOffsetX = Array(repeating: 0, count: 5)
        cardOffsetY = Array(repeating: 0, count: 5)
        cardScale = Array(repeating: 0.6, count: 5)
        cardOpacity = Array(repeating: 0, count: 5)
        cardRotation = Array(repeating: 0, count: 5)
    }

    func isMuseumComplete(_ museumId: String) -> Bool {
        let artworks = CardDatabase.artworksFor(location: museumId)
        let revealed = CardDatabase.getRevealedCards()
        return !artworks.isEmpty && artworks.allSatisfy { revealed.contains($0) }
    }

    private var completionModal: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCompletionModal = false
                    }
                }
                .accessibilityHidden(true)

            VStack(spacing: 28) {
                Text("GREAT NEWS!")
                    .font(.custom("Helvetica-BoldOblique", size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF5E3A"), Color(hex: "FF9500")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 20)
                    .minimumScaleFactor(0.8)

                VStack(spacing: 6) {
                    Text("Looks like you're having a great time exploring!")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("You've already completed this collection.")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("\(Text("Go ").font(.custom("Helvetica-Oblique", size: 15)).foregroundStyle(.white.opacity(0.7)))\(Text("Keep").font(.custom("Helvetica-BoldOblique", size: 15)).foregroundStyle(.white))\(Text(" another one!").font(.custom("Helvetica-Oblique", size: 15)).foregroundStyle(.white.opacity(0.7)))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 16)

                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCompletionModal = false
                    }
                }) {
                    Text("KEEP EXPLORING")
                        .font(.custom("Helvetica-BoldOblique", size: 15))
                        .foregroundStyle(.black)
                        .frame(width: 240, height: 50)
                        .background(
                            Capsule().fill(Color(hex: "D8D8D8"))
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
        }
    }
}

#Preview {
    PackOpeningView(activeView: .constant(.opening))
}
