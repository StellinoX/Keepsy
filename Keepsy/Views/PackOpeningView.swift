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
    @State private var packIdleSway: Double = 0

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
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            packState = .tearing
                        }
                    },
                    onTapActivePack: {
                        onTapActivePack()
                    },
                    onTapCity: {
                        showCitySelector = true
                    }
                )
            } else {
                ZStack {
                    if packState == .tearing || packState == .opened {
                        ZStack {
                            SceneKitPacketView(
                                museumId: selectedMuseumId,
                                packetImageName: selectedMuseumId == "capodimonte" ? "capodimonte_pacchetto" : "uffizi_pacchetto",
                                onTearComplete: {
                                    showOpeningEffect = true
                                    triggerShake()
                                    withAnimation(.easeOut(duration: 0.02)) { flashOpacity = 0.8 }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                        withAnimation(.easeIn(duration: 0.28)) { flashOpacity = 0.0 }
                                    }
                                    if !UserDefaults.standard.bool(forKey: "hasPlayedSanSebastianoSound") {
                                        SoundManager.shared.playSound(named: "san sebastiano")
                                        UserDefaults.standard.set(true, forKey: "hasPlayedSanSebastianoSound")
                                    }
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
                        .rotationEffect(.degrees(packIdleSway), anchor: .bottom)
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
                                    Text("CATCH'EM")
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
            if synced && packState == .opened { loadActivePack() }
        }
        .onChange(of: packState) { _, newState in
            if newState == .tearing {
                showTearHint = false
                packIdleSway = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard packState == .tearing, !showOpeningEffect else { return }
                    withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                        packIdleSway = 1.5
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    guard packState == .tearing, !showOpeningEffect else { return }
                    withAnimation(.easeIn(duration: 0.4)) { showTearHint = true }
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { showTearHint = false }
                packIdleSway = 0
            }
        }
        .onChange(of: showOpeningEffect) { _, firing in
            if firing {
                withAnimation(.easeOut(duration: 0.15)) { showTearHint = false }
                packIdleSway = 0
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
        packIdleSway = 0
        shimmerPhase = 0
        nextButtonScale = 0

        cardOffsetX = [123, 0, -123, 61.5, -61.5]
        cardOffsetY = [94, 94, 94, -94, -94]
        cardScale = Array(repeating: 1.0, count: 5)
        cardOpacity = Array(repeating: 0, count: 5)
        cardRotation = [-4, 2, -2, 3, 0]
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
    @State private var carouselDragOffset: CGFloat = 0

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
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.white)
                    Text("Keeper")
                        .font(.custom("Helvetica-BoldOblique", size: 38))
                        .italic()
                        .bold()
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

                // Pacchetti divisi per museo — scorri orizzontalmente in stile Pokemon Pocket
                ZStack {
                    ForEach(Array(museums.enumerated()), id: \.element.id) { index, museum in
                        let diff = CGFloat(index - selectedIndex)
                        
                        // Il pacchetto centrale è in scala 1.25, quelli adiacenti sono più piccoli e sfumati
                        let isSelected = index == selectedIndex
                        let scale: CGFloat = isSelected ? 1.25 : 0.88
                        let opacity: Double = isSelected ? 1.0 : 0.65
                        
                        // Rotazione stile Pokemon: pacchetto sinistro ruotato a sx (-5°), destro a dx (+5°)
                        let rotation: Double = isSelected ? 0 : (diff > 0 ? 5 : -5)
                        
                        // Offset: più stretto per far vedere chiaramente i pacchetti laterali come da Sketch
                        let xOffset = diff * 190 + carouselDragOffset
                        
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
                        .zIndex(isSelected ? 10 : 1)
                    }
                }
                .frame(height: 400)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { gesture in
                            // Traccia solo trascinamenti prevalentemente orizzontali per non bloccare lo scroll verticale della ScrollView
                            if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                carouselDragOffset = gesture.translation.width
                            }
                        }
                        .onEnded { gesture in
                            let velocity = gesture.predictedEndTranslation.width
                            let threshold: CGFloat = 50
                            
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                    if gesture.translation.width < -threshold || velocity < -200 {
                                        // Swipe a sinistra -> pacchetto successivo
                                        let nextIndex = min(selectedIndex + 1, museums.count - 1)
                                        selectedMuseumId = museums[nextIndex].id
                                    } else if gesture.translation.width > threshold || velocity > 200 {
                                        // Swipe a destra -> pacchetto precedente
                                        let prevIndex = max(selectedIndex - 1, 0)
                                        selectedMuseumId = museums[prevIndex].id
                                    }
                                }
                                carouselDragOffset = 0
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
        }
    }

    private var locationChip: some View {
        HStack(spacing: 5) {
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
            Text(displayedCity)
                .font(.system(size: 11, weight: .black))
                .italic()
                .foregroundColor(.white)
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .frame(width: 109, height: 30)
        .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 2))
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

    var body: some View {
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
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "activePackTearMask_\(museum.id)")
                ?? UserDefaults.standard.data(forKey: "activePackTearMask") {
                savedTearMask = UIImage(data: data)
            }
        }
    }
}

struct PackExpansionRow: View {
    let museumId: String
    let title: String
    let progress: Double
    let onTap: () -> Void
    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    var body: some View {
        let imageName = MuseumConfig.shared.museums.first(where: { $0.id == museumId })?.packetImageName ?? "uffizi_pacchetto"
        return Button(action: onTap) {
            HStack(spacing: 0) {
                // Left side: Zoomed, fanned, and clipped packets
                ZStack {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 130, height: 195)
                        .rotationEffect(.degrees(-10))
                        .offset(x: -20, y: 8)
                    
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 130, height: 195)
                        .rotationEffect(.degrees(10))
                        .offset(x: 15, y: 18)
                }
                .frame(width: 140, height: 194)
                .offset(x: 8, y: 0)
                
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
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2C2C2E"), Color(hex: "121214")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isComplete ?
                            LinearGradient(colors: [Color(hex: "F2CA03"), Color(hex: "C7A245")], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color(hex: "B1B1B1"), Color(hex: "464646")], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16)) // Clip packets to card shape
            .shadow(color: Color.black.opacity(0.5), radius: 39, x: 0, y: 4)
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

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: UIScreen.main.bounds.height * 0.31)

            VStack(spacing: 10) {
                // Striscia luminosa con sweep
                ZStack {
                    // Glow halo dietro la riga
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(maxWidth: .infinity, maxHeight: 8)
                        .blur(radius: 4)
                        .opacity(glowOpacity)

                    // Riga principale bold
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .white.opacity(0.95), .white.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity, maxHeight: 3)
                        .opacity(glowOpacity)

                    // Sweep luminoso
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, .white, .white, .clear],
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

            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerX = 180
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glowOpacity = 0.9
            }
        }
    }
}

struct PackOpeningView_Previews: PreviewProvider {
    static var previews: some View {
        PackOpeningView(activeView: .constant(.opening))
    }
}
