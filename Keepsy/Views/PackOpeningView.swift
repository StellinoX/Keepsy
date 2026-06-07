import SwiftUI

struct LocationContainer: Identifiable {
    let id = UUID()
    let name: String
}

struct PackOpeningView: View {
    @Binding var activeView: ContentView.ActiveView
    @StateObject private var locationManager = LocationManager()
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
    @State private var flashOpacity: Double = 0.0
    @State private var showOpeningEffect = false
    @State private var shakeOffset: CGFloat = 0
    @State private var showTearHint = false
    @State private var packSwayX: CGFloat = 0
    @State private var showCompletionModal = false

    // Animazione carte — una per carta
    @State private var cardOffsetX: [CGFloat] = [123, 0, -123, 61.5, -61.5]
    @State private var cardOffsetY: [CGFloat] = [94, 94, 94, -94, -94]
    @State private var cardScale: [CGFloat] = Array(repeating: 1.0, count: 5)
    @State private var cardOpacity: [Double] = Array(repeating: 0, count: 5)
    @State private var cardRotation: [Double] = Array(repeating: 0, count: 5)
    @State private var shimmerPhase: CGFloat = 0
    @State private var nextButtonScale: CGFloat = 0

    var body: some View {
        ZStack {
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
                PackOpeningFlashView(isTriggered: showOpeningEffect) {
                    showOpeningEffect = false
                }
                .zIndex(5)
                .allowsHitTesting(false)

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
                } else if packState == .packSelection {
                    PackSelectionView(
                        museumId: selectedMuseumId,
                        onPacketSelected: {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) {
                                packState = .tearing
                            }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) {
                                packState = .selecting
                            }
                        }
                    )
                }
            else {
                ZStack {
                    if packState == .tearing {
                        ZStack {
                            SceneKitPacketView(
                                museumId: selectedMuseumId,
                                packetImageName: MuseumConfig.shared.museums.first(where: { $0.id == selectedMuseumId })?.packetImageName ?? "uffizi_pacchetto",
                                onTearComplete: {
                                    showOpeningEffect = true
                                    triggerShake()
                                    withAnimation(.easeOut(duration: 0.02)) { flashOpacity = 0.8 }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                        withAnimation(.easeIn(duration: 0.28)) { flashOpacity = 0.0 }
                                    }
                                    SoundManager.shared.playSound(named: "san sebastiano")
                                },
                                onOpen: {
                                    completeOpening()
                                }
                            )
                            .ignoresSafeArea()

                            if packState == .tearing && showTearHint && !showOpeningEffect {
                                PackTearHintView()
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .ignoresSafeArea()
                        .offset(x: packSwayX)
                        .transition(.identity)
                        .zIndex(10)
                    }

                    if packState == .opened {
                        VStack {
                            Spacer()

                            ZStack {
                                VStack(spacing: 20) {
                                    // Riga 1: carte 0,1,2
                                    HStack(spacing: 12) {
                                        ForEach(0..<3, id: \.self) { index in
                                            if index < cards.count {
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
                                    // Riga 2: carte 3,4
                                    HStack(spacing: 12) {
                                        ForEach(3..<5, id: \.self) { index in
                                            if index < cards.count {
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
                                    Text("KEEP'EM")
                                        .font(.custom("Helvetica-BoldOblique", size: 20))
                                        .foregroundColor(.black)
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
                            }
                        }
                        .zIndex(20)
                    }
                }
                .offset(x: shakeOffset)
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
                    .foregroundColor(.white)
                    .frame(width: 85, height: 44)
                    .background(
                        Capsule().fill(Color(hex: "383838"))
                    )
                }
                .position(x: 30 + 85/2, y: 83 + 44/2)
                .zIndex(150)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard packState == .tearing, !showOpeningEffect else { return }
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        packSwayX = 9
                    }
                }
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

        cardOffsetX = [123, 0, -123, 61.5, -61.5]
        cardOffsetY = [94, 94, 94, -94, -94]
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
        
        let selectedArtworks = Array(remainingArtworks.shuffled().prefix(5))

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
        
        cardOffsetX = [123, 0, -123, 61.5, -61.5]
        cardOffsetY = [94, 94, 94, -94, -94]
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
            // Semi-transparent dim background
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCompletionModal = false
                    }
                }
            
            // Modal Card
            VStack(spacing: 28) {
                // Title
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
                
                // Description Text
                VStack(spacing: 6) {
                    Text("Looks like you're having a great time exploring!")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    Text("You've already completed this collection.")
                        .font(.custom("Helvetica-Oblique", size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    
                    (
                        Text("Go ")
                            .font(.custom("Helvetica-Oblique", size: 15))
                            .foregroundColor(.white.opacity(0.7))
                        + Text("Keep")
                            .font(.custom("Helvetica-BoldOblique", size: 15))
                            .foregroundColor(.white)
                        + Text(" another one!")
                            .font(.custom("Helvetica-Oblique", size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 16)
                
                // Keep Exploring Button
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCompletionModal = false
                    }
                }) {
                    Text("KEEP EXPLORING")
                        .font(.custom("Helvetica-BoldOblique", size: 15))
                        .foregroundColor(.black)
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
        }
    }
}

// MARK: - SingleScrollPackView

struct SingleScrollPackView: View {
    @Binding var activeView: ContentView.ActiveView
    let currentCity: String
    @Binding var selectedMuseumId: String
    let onStart: () -> Void
    let onTapActivePack: () -> Void
    let onTapCity: () -> Void

    @State private var revealedCards: Set<String> = []
    @State private var scrollPosition: CGFloat = 0.0
    @State private var baseScrollPosition: CGFloat = 0.0
    @State private var isDragging: Bool = false

    private var museums: [Museum] { MuseumConfig.shared.museums }

    private var selectedIndex: Int {
        museums.firstIndex(where: { $0.id == selectedMuseumId }) ?? 0
    }

    // The museum whose pack is currently opened (awaiting AR scan), if any.
    // Falls back to the first museum so a pack opened before museum separation
    // existed (no stored "currentCity") still surfaces instead of orphaning.
    private var activePackMuseum: String? {
        guard CardDatabase.hasActivePack() else { return nil }
        return UserDefaults.standard.string(forKey: "currentCity") ?? museums.first?.id
    }

    private var displayedCity: String {
        switch selectedMuseumId {
        case "capodimonte": return "NAPLES"
        case "uffizi":      return "FLORENCE"
        case "prado":       return "MADRID"
        case "moma":        return "NEW YORK"
        default:
            let city = currentCity.uppercased()
            if city == "NAPOLI" { return "NAPLES" }
            if city == "FIRENZE" { return "FLORENCE" }
            return city.isEmpty ? "NAPLES" : city
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Header (Hello, Keeper) — scrolls with content
                VStack(alignment: .leading, spacing: -4) {
                    Text("Hello,")
                        .font(.custom("Helvetica-Light", size: 24))
                        .foregroundColor(.white)
                    Text("Keeper")
                        .font(.custom("Helvetica-BoldOblique", size: 38))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 95)
                .padding(.bottom, 20)

                locationChip
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapCity()
                    }
                    .padding(.top, 0)
                    .padding(.bottom, 20)

                // Pacchetti divisi per museo — scorri orizzontalmente in stile Pokemon Pocket (Infinito Circular/Pacman style)
                ZStack {
                    ForEach(Array(museums.enumerated()), id: \.element.id) { index, museum in
                        let diff = circularDifference(index: index, scrollPosition: scrollPosition, count: museums.count)
                        let absDiff = abs(diff)
                        
                        // Continuous layout calculations for smooth Pokemon Pocket style scrolling
                        let scale: CGFloat = 1.25 - min(absDiff, 1.0) * (1.25 - 0.88)
                        
                        let opacity: Double = {
                            if absDiff > 1.1 {
                                return 0.0
                            } else if absDiff <= 1.0 {
                                return 1.0 - absDiff * (1.0 - 0.65)
                            } else {
                                let t = (absDiff - 1.0) / 0.1
                                return 0.65 * (1.0 - t)
                            }
                        }()
                        
                        let rotation: Double = {
                            let maxRot: Double = 5.0
                            if diff > 1.0 {
                                return maxRot
                            } else if diff < -1.0 {
                                return -maxRot
                            } else {
                                return Double(diff) * maxRot
                            }
                        }()
                        
                        let xOffset = diff * 190
                        let zIndexValue = 10.0 - absDiff
                        
                        MuseumPackPage(
                            museum: museum,
                            revealedCards: revealedCards,
                            onTapActivePack: onTapActivePack,
                            onTapStart: onStart
                        )
                        .frame(width: 380, height: 515)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .rotationEffect(.degrees(rotation))
                        .offset(x: xOffset)
                        .zIndex(zIndexValue)
                    }
                }
                .frame(height: 400)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { gesture in
                            if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                if !isDragging {
                                    isDragging = true
                                    baseScrollPosition = scrollPosition
                                }
                                scrollPosition = baseScrollPosition - gesture.translation.width / 190
                            }
                        }
                        .onEnded { gesture in
                            isDragging = false
                            let velocity = gesture.predictedEndTranslation.width
                            let threshold: CGFloat = 50
                            
                            var indexChange = 0
                            if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                if gesture.translation.width < -threshold || velocity < -200 {
                                    indexChange = 1
                                } else if gesture.translation.width > threshold || velocity > 200 {
                                    indexChange = -1
                                }
                            }
                            
                            let count = museums.count
                            let targetIndex = (selectedIndex + indexChange + count) % count
                            let targetScrollPosition = CGFloat(selectedIndex + indexChange)
                            
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                scrollPosition = targetScrollPosition
                                selectedMuseumId = museums[targetIndex].id
                            }
                            
                            // Normalize scroll position post-animation to keep coordinates within clean range [0, count)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    scrollPosition = CGFloat(targetIndex)
                                    baseScrollPosition = scrollPosition
                                }
                            }
                        }
                )

                // Bottone statico: cambia stato in base al museo selezionato, non scorre
                let isSelectedActive = CardDatabase.hasActivePack(for: selectedMuseumId)
                Button(action: isSelectedActive ? onTapActivePack : onStart) {
                    Text(isSelectedActive ? "CONTINUE" : "START")
                        .font(.custom("Helvetica-BoldOblique", size: 15))
                        .foregroundColor(.black)
                        .frame(width: isSelectedActive ? 130 : 110, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 19)
                                .fill(LinearGradient(
                                    colors: [.white, Color(hex: "EAEAEA")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .shadow(color: .black.opacity(0.55), radius: 39, x: 0, y: 4)
                        )
                }
                .padding(.top, 25)
                .padding(.bottom, 36)
                .animation(.easeInOut(duration: 0.2), value: selectedMuseumId)

                // Collezioni divise per museo
                VStack(spacing: 14) {
                    ForEach(museums) { museum in
                        let info = progressFor(museum.id)
                        PackExpansionRow(
                            museumId: museum.id,
                            title: museum.name,
                            progress: info.progress,
                            onTap: {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    activeView = .collection(museum.id)
                                }
                            }
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
            if let index = museums.firstIndex(where: { $0.id == selectedMuseumId }) {
                scrollPosition = CGFloat(index)
                baseScrollPosition = CGFloat(index)
            }
        }
        .onChange(of: selectedMuseumId) { _, newValue in
            if let index = museums.firstIndex(where: { $0.id == newValue }) {
                let targetPos = CGFloat(index)
                let diff = circularDifference(index: index, scrollPosition: scrollPosition, count: museums.count)
                if abs(diff) > 0.01 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        scrollPosition = targetPos
                    }
                }
            }
        }
    }

    private var locationChip: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 20, height: 20)
            .padding(.leading, 6)
            
            Text(displayedCity)
                .font(.custom("Helvetica-BoldOblique", size: 11))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.trailing, 10)
        }
        .frame(width: 109, height: 30)
        .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 2))
    }

    func progressFor(_ museumId: String) -> (progress: Double, found: Int, total: Int) {
        let artworks = CardDatabase.artworksFor(location: museumId)
        let found = artworks.filter { revealedCards.contains($0) }.count
        return (artworks.isEmpty ? 0 : Double(found) / Double(artworks.count), found, artworks.count)
    }

    private func circularDifference(index: Int, scrollPosition: CGFloat, count: Int) -> CGFloat {
        let c = CGFloat(count)
        let rawDiff = CGFloat(index) - scrollPosition
        var diff = rawDiff.truncatingRemainder(dividingBy: c)
        let half = c / 2
        if diff > half {
            diff -= c
        } else if diff <= -half {
            diff += c
        }
        return diff
    }
}

// MARK: - MuseumPackPage — una pagina del pager, il pacchetto di un singolo museo

struct MuseumPackPage: View {
    let museum: Museum
    let revealedCards: Set<String>
    let onTapActivePack: () -> Void
    let onTapStart: () -> Void

    @State private var savedTearMask: UIImage? = nil

    private var packetImage: String {
        museum.packetImageName
    }

    private var activePack: [String]? {
        guard CardDatabase.hasActivePack(for: museum.id),
              let pack = CardDatabase.getActivePack(for: museum.id),
              !pack.isEmpty else { return nil }
        return pack
    }

    private var isComplete: Bool {
        let artworks = CardDatabase.artworksFor(location: museum.id)
        return !artworks.isEmpty && artworks.allSatisfy { revealedCards.contains($0) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let activePack = activePack {
                    // Pack strappato con carta che spunta — serve SceneKit
                    let firstCardName = activePack[0]
                    SceneKitPacketView(interactive: false, isTorn: true,
                                       museumId: museum.id,
                                       packetImageName: packetImage,
                                       firstCardName: firstCardName,
                                       isFirstCardRevealed: revealedCards.contains(firstCardName),
                                       tearMaskImage: savedTearMask)
                        .frame(width: 380, height: 515)
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapActivePack() }
                } else {
                    // Pack sigillato — usiamo SceneKit in 3D per avere esattamente le stesse dimensioni, prospettiva ed ombra del pack aperto!
                    SceneKitPacketView(interactive: false, isTorn: false,
                                       museumId: museum.id,
                                       packetImageName: packetImage)
                        .frame(width: 380, height: 515)
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapStart() }
                }
            }
            .padding(.top, 4)
            .colorMultiply(isComplete ? Color(white: 0.72) : .white)
            
            if isComplete {
                let ipadScale = (UIDevice.current.userInterfaceIdiom == .pad) ? 1.4 : 1.0
                Image("check")
                    .resizable()
                    .padding(4 * ipadScale)
                    .frame(width: 55 * ipadScale, height: 55 * ipadScale)
                    .shadow(color: Color.black.opacity(0.35), radius: 8 * ipadScale, x: 0, y: 4 * ipadScale)
                    .offset(x: 75 * ipadScale, y: -125 * ipadScale)
            }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "activePackTearMask_\(museum.id)")
                ?? UserDefaults.standard.data(forKey: "activePackTearMask") {
                savedTearMask = UIImage(data: data)
            }
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    var percentText: String
    
    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .frame(width: 32, height: 32)
            
            // Progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90)) // Start from top
            
            // Percentage text
            Text(percentText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 32, height: 32)
    }
}

struct CompletedBadgeView: View {
    var x: CGFloat = 0
    var y: CGFloat = 0

    var body: some View {
        let ipadScale = (UIDevice.current.userInterfaceIdiom == .pad) ? 1.4 : 1.0
        Image("check")
            .resizable()
            .padding(3 * ipadScale)
            .frame(width: 62 * ipadScale, height: 62 * ipadScale)
            .offset(x: -17 * ipadScale, y: -17 * ipadScale)
    }
}

struct PackExpansionRow: View {
    let museumId: String
    let title: String
    let progress: Double
    let onTap: () -> Void
    
    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    private var subtitle: String {
        switch museumId {
        case "uffizi":      return "Florence, Italy"
        case "prado":       return "Madrid, Spain"
        case "capodimonte": return "Naples, Italy"
        case "moma":        return "New York, NY"
        default:            return ""
        }
    }

    private var fannedPacketsView: some View {
        let imageName = MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"
        let ipadScale = (UIDevice.current.userInterfaceIdiom == .pad) ? 1.4 : 1.0
        return ZStack(alignment: .bottom) {
            // Left packet
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .rotationEffect(.degrees(-12))
                .offset(x: -40 * ipadScale, y: 75 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)
            
            // Right packet
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .rotationEffect(.degrees(12))
                .offset(x: 40 * ipadScale, y: 75 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)

            // Center packet (on top of the others)
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 125 * ipadScale, height: 187 * ipadScale)
                .offset(x: 0, y: 65 * ipadScale)
                .colorMultiply(isComplete ? Color(white: 0.72) : Color.white)
        }
    }

    private var headerView: some View {
        ZStack(alignment: .top) {
            // Centered Text
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.custom("Helvetica-BoldOblique", size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF7A00"), Color(hex: "FFB800")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(subtitle)
                    .font(.custom("Helvetica-Oblique", size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            
            // Leading/Trailing items overlay
            HStack(alignment: .center) {
                if isComplete {
                    CompletedBadgeView()
                } else {
                    CircularProgressView(progress: progress, percentText: percentText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .top) {
                fannedPacketsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "151517"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        Color.white.opacity(0.12),
                        lineWidth: 1.0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.55), radius: 30, x: 0, y: 15)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - PacketFoilImageView — asset 2D con effetto metallico (nessun SceneKit)

struct PacketFoilImageView: View {
    let imageName: String
    var maxHeight: CGFloat = 225

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(sin(time * 0.72)) * 0.82

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .overlay(
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height

                        ZStack {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.04),
                                    Color(red: 0.78, green: 0.82, blue: 0.86).opacity(0.10),
                                    .white.opacity(0.05),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .blendMode(.screen)

                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(0.03),
                                            .white.opacity(0.22),
                                            Color(red: 0.72, green: 0.76, blue: 0.80).opacity(0.14),
                                            .white.opacity(0.03),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: w * 0.34, height: h * 1.35)
                                .rotationEffect(.degrees(18))
                                .offset(x: phase * w)
                                .blur(radius: 9)
                                .blendMode(.screen)
                                .opacity(0.55)
                        }
                    }
                    .allowsHitTesting(false)
                )
                .mask(
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: maxHeight)
                )
        }
    }
}

// MARK: - PackOpeningFlashView — warm gold burst

struct SparkParticle: Identifiable {
    let id = UUID()
    let size: CGFloat
    let angle: Double
    let speed: CGFloat
    let color: Color
}

struct PackOpeningFlashView: View {
    var isTriggered: Bool
    var onComplete: () -> Void

    @State private var burstScale: CGFloat = 0.1
    @State private var burstOpacity: Double = 0.0
    @State private var rayRotation: Double = 0
    @State private var rayRotation2: Double = 0
    @State private var rayOpacity: Double = 0.0
    @State private var rayScale: CGFloat = 0.3
    @State private var ring1Scale: CGFloat = 0.1
    @State private var ring1Opacity: Double = 0.0
    @State private var ring2Scale: CGFloat = 0.1
    @State private var ring2Opacity: Double = 0.0
    @State private var sparkOpacity: Double = 0.0
    @State private var sparkScale: CGFloat = 0.15
    @State private var globalOpacity: Double = 0.0 // starts invisible to avoid mount lag
    @State private var particles: [SparkParticle] = []

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
                    Color(hex: "F5E480").opacity(0.95),
                    Color(hex: "F1B40A").opacity(0.65),
                    Color(hex: "9A6F00").opacity(0.3),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .blendMode(.screen)

            // 2. Dual Gold rays layers
            // Layer 1: Clockwise rays
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [
                                .clear,
                                Color(hex: "F5E480").opacity(0.35),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 1.5 + CGFloat(i % 3) * 1.0, height: 750)
                        .rotationEffect(.degrees(Double(i) * 22.5))
                }
            }
            .drawingGroup()
            .rotationEffect(.degrees(rayRotation))
            .blur(radius: 1.5)
            .scaleEffect(rayScale)
            .opacity(rayOpacity)
            .blendMode(.screen)

            // Layer 2: Counter-clockwise rays
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [
                                .clear,
                                Color(hex: "FFAC1C").opacity(0.25),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 2.0 + CGFloat(i % 2) * 1.5, height: 700)
                        .rotationEffect(.degrees(Double(i) * 30.0))
                }
            }
            .drawingGroup()
            .rotationEffect(.degrees(rayRotation2))
            .blur(radius: 2.0)
            .scaleEffect(rayScale * 0.9)
            .opacity(rayOpacity * 0.8)
            .blendMode(.screen)

            // 3. Inner ring — gold gradient expanding and fading
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4.0
                )
                .frame(width: 190, height: 190)
                .scaleEffect(ring1Scale)
                .opacity(ring1Opacity)
                .blur(radius: 1.0)
                .blendMode(.screen)

            // 4. Outer ring — softer gold, delayed expansion
            Circle()
                .stroke(Color(hex: "FFAC1C").opacity(0.4), lineWidth: 2.5)
                .frame(width: 290, height: 290)
                .scaleEffect(ring2Scale)
                .opacity(ring2Opacity)
                .blur(radius: 2.5)
                .blendMode(.screen)

            // 5. Ember sparks flying outward organically
            ZStack {
                ForEach(particles) { p in
                    let distance = p.speed * 320.0 * sparkScale
                    Circle()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .offset(x: cos(p.angle) * distance,
                                y: sin(p.angle) * distance)
                }
            }
            .drawingGroup()
            .blur(radius: 1.0)
            .opacity(sparkOpacity)
            .blendMode(.screen)
        }
        .opacity(globalOpacity)
        .ignoresSafeArea()
        .onChange(of: isTriggered) { _, newValue in
            if newValue {
                runAnimation()
            }
        }
    }

    func runAnimation() {
        // Reset all states immediately to baseline (no animations)
        burstScale = 0.1
        burstOpacity = 1.0
        rayScale = 0.3
        rayOpacity = 1.0
        rayRotation = 0
        rayRotation2 = 0
        ring1Scale = 0.1
        ring1Opacity = 1.0
        ring2Scale = 0.1
        ring2Opacity = 0.8
        sparkScale = 0.1
        sparkOpacity = 1.0
        
        // Generate new particles
        self.particles = (0..<24).map { i in
            let angle = Double.random(in: 0...(2 * Double.pi))
            let size = CGFloat.random(in: 3...9)
            let speed = CGFloat.random(in: 0.6...1.4)
            let colors: [Color] = [
                Color(hex: "FFF9D6"), Color(hex: "F5E480"),
                Color(hex: "F1B40A"), Color(hex: "FFAC1C"),
                Color(hex: "FF7F50"), Color(white: 1.0)
            ]
            let color = colors[i % colors.count]
            return SparkParticle(size: size, angle: angle, speed: speed, color: color)
        }
        
        // Make the container visible immediately
        globalOpacity = 1.0
        
        // Run smooth expand-and-fade animations over longer durations (0.65s - 0.8s) for fluid rendering
        withAnimation(.easeOut(duration: 0.68)) {
            burstScale = 3.5
            burstOpacity = 0.0
        }
        
        withAnimation(.easeOut(duration: 0.75)) {
            rayScale = 2.4
            rayOpacity = 0.0
        }
        
        withAnimation(.easeOut(duration: 0.82)) {
            rayRotation = 270
            rayRotation2 = -320
        }
        
        withAnimation(.easeOut(duration: 0.7)) {
            ring1Scale = 5.2
            ring1Opacity = 0.0
        }
        
        withAnimation(.easeOut(duration: 0.78).delay(0.04)) {
            ring2Scale = 6.2
            ring2Opacity = 0.0
        }
        
        withAnimation(.easeOut(duration: 0.72)) {
            sparkScale = 1.3
            sparkOpacity = 0.0
        }
        
        // Smoothly fade the global container at the end
        withAnimation(.easeIn(duration: 0.2).delay(0.65)) {
            globalOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            onComplete()
        }
    }
}

// MARK: - PackTearHintView — striscia luminosa + frecce per guidare l'apertura

struct PackTearHintView: View {
    @State private var shimmerX: CGFloat = -180
    @State private var glowOpacity: Double = 0.2
    @State private var handOffset: CGFloat = -40
    @State private var textOpacity: Double = 1.0

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            ZStack {
                // SWIPE RIGHT TO OPEN text & hand icon
                VStack(spacing: 6) {
                    Text("SWIPE RIGHT")
                        .font(.custom("Helvetica-BoldOblique", size: 20))
                        .foregroundColor(Color(hex: "FF7A00"))
                        .italic()
                        .bold()
                        .shadow(color: Color(hex: "FF7A00").opacity(0.3), radius: 4)
                    
                    Text("TO OPEN")
                        .font(.custom("Helvetica-BoldOblique", size: 20))
                        .foregroundColor(Color(hex: "FF7A00"))
                        .italic()
                        .bold()
                        .shadow(color: Color(hex: "FF7A00").opacity(0.3), radius: 4)
                    
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.8))
                        .offset(x: handOffset)
                        .padding(.top, 4)
                }
                .opacity(textOpacity)
                .position(x: screenWidth / 2, y: screenHeight * 0.27)
                
                // Horizontal Orange Glowing Line & Shimmer
                ZStack {
                    // Glow halo behind the line
                    Rectangle()
                        .fill(Color(hex: "FF7A00").opacity(0.25))
                        .frame(maxWidth: .infinity, maxHeight: 8)
                        .blur(radius: 4)
                        .opacity(glowOpacity)

                    // Main bold orange line
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "FF7A00").opacity(0.55), Color(hex: "FF7A00").opacity(0.95), Color(hex: "FF7A00").opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity, maxHeight: 3)
                        .opacity(glowOpacity)

                    // Yellow/Orange Shimmer sweep
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: "FFB800"), Color(hex: "FFB800"), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: 110, height: 3)
                        .blur(radius: 1)
                        .offset(x: shimmerX)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 8)
                .clipped()
                .padding(.horizontal, 24)
                .position(x: screenWidth / 2, y: screenHeight * 0.55)
            }
            .frame(width: screenWidth, height: screenHeight)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerX = 180
                }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.9
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    handOffset = 40
                }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    textOpacity = 0.25
                }
            }
        }
    }
}

struct PackOpeningView_Previews: PreviewProvider {
    static var previews: some View {
        PackOpeningView(activeView: .constant(.opening))
    }
}
