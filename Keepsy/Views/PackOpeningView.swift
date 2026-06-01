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
                            Spacer()
                            if cards.allSatisfy({ $0.isFlipped }) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        activeView = .arScanner
                                    }
                                    // Reset the pack selection state only after the transition completes
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        resetPack()
                                    }
                                }) {
                                    Text("NEXT")
                                        .font(.system(.headline, design: .monospaced))
                                        .bold()
                                        .frame(width: 240, height: 50)
                                        .background(Capsule().fill(Color(white: 0.9)))
                                        .foregroundColor(.black)
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
        // 1. Fai comparire le carte sovrapposte al centro (opacità = 1)
        for index in 0..<5 {
            cardOffsetX[index] = [123.0, 0.0, -123.0, 61.5, -61.5][index]
            cardOffsetY[index] = [94.0, 94.0, 94.0, -94.0, -94.0][index]
            cardScale[index] = 1.0
            cardOpacity[index] = 1.0
            cardRotation[index] = [-4.0, 2.0, -2.0, 3.0, 0.0][index]
        }
        
        // 2. Dopo 0.2s, allarga e disponi le carte verso le loro posizioni nella griglia
        let delays: [Double] = [0.0, 0.08, 0.16, 0.10, 0.18]
        
        for index in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 + delays[index]) {
                HapticManager.shared.triggerImpact(style: .medium)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    cardOffsetX[index] = 0
                    cardOffsetY[index] = 0
                    cardRotation[index] = 0
                }
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
                .frame(height: 490)

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
            Text(museum.name)
                .font(.system(size: 22, weight: .black)).italic()
                .foregroundColor(.white)
                .padding(.bottom, 10)

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
                // ZStack con le due bustine che sporgono (overflow)
                ZStack {
                    SceneKitPacketView(interactive: false)
                        .frame(width: 104, height: 154)
                        .rotationEffect(.degrees(-11))
                        .offset(x: -12, y: 0)
                    
                    SceneKitPacketView(interactive: false)
                        .frame(width: 104, height: 154)
                        .rotationEffect(.degrees(12))
                        .offset(x: 18, y: 8)
                }
                .frame(width: 140, height: 142) // Area sinistra senza clipping
                
                Spacer()
                
                // Contenuto di destra
                VStack(alignment: .trailing, spacing: 0) {
                    // Chevron in alto a destra
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 18)
                        .padding(.trailing, 20)
                    
                    Spacer()
                    
                    // Nome museo + percentuale + barra di progresso in basso a destra
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold)).italic()
                            .foregroundColor(.white.opacity(0.85))
                        Text(percentText)
                            .font(.system(size: 28, weight: .bold)).italic()
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
            .frame(width: 350, height: 142)
            // Sfondo arrotondato per non clippare le bustine che sporgono!
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "1F1F21")) // Grigio scuro del design
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                isComplete ?
                                    LinearGradient(colors: [Color(hex: "F2CA03"), Color(hex: "C7A245")], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - PackOpeningFlashView — effetto apertura stile Pokemon Pocket

struct PackOpeningFlashView: View {
    var onComplete: () -> Void

    // Burst radiale
    @State private var burstScale: CGFloat = 0.1
    @State private var burstOpacity: Double = 0.0

    // Raggi rotanti — veloci
    @State private var rayRotation: Double = 0
    @State private var rayOpacity: Double = 0.0
    @State private var rayScale: CGFloat = 0.3

    // Secondo layer raggi (counter-rotate, colore diverso)
    @State private var ray2Rotation: Double = 0
    @State private var ray2Opacity: Double = 0.0

    // Ring esplosivo
    @State private var ringScale: CGFloat = 0.1
    @State private var ringOpacity: Double = 0.0

    // Scintille
    @State private var sparkOpacity: Double = 0.0
    @State private var sparkScale: CGFloat = 0.2

    // Fade out generale
    @State private var globalOpacity: Double = 1.0

    let rayColors: [Color] = [
        Color(hex: "00CFFF"),  // ciano elettrico
        Color(hex: "FFFFFF"),  // bianco
        Color(hex: "7B2FFF"),  // viola
        Color(hex: "00CFFF"),
        Color(hex: "FFFFFF"),
        Color(hex: "FFD700"),  // oro
    ]

    var body: some View {
        ZStack {
            // 1. Burst radiale centrale — esplode verso l'esterno
            RadialGradient(
                colors: [
                    Color.white.opacity(0.95),
                    Color(hex: "00CFFF").opacity(0.7),
                    Color(hex: "7B2FFF").opacity(0.4),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 320
            )
            .scaleEffect(burstScale)
            .opacity(burstOpacity)
            .blendMode(.screen)

            // 2. Raggi veloci layer 1 — ciano/bianco
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    rayColors[i % rayColors.count].opacity(0.55),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3 + CGFloat(i % 4) * 2, height: 700)
                        .rotationEffect(.degrees(Double(i) * (360.0 / 16.0) + rayRotation))
                }
            }
            .blur(radius: 3)
            .scaleEffect(rayScale)
            .opacity(rayOpacity)
            .blendMode(.screen)

            // 3. Raggi veloci layer 2 — oro/viola, counter-rotate
            ZStack {
                ForEach(0..<10, id: \.self) { i in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    (i % 2 == 0 ? Color(hex: "FFD700") : Color(hex: "7B2FFF")).opacity(0.45),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 5 + CGFloat(i % 3) * 3, height: 800)
                        .rotationEffect(.degrees(Double(i) * 36.0 + ray2Rotation))
                }
            }
            .blur(radius: 5)
            .scaleEffect(rayScale * 1.1)
            .opacity(ray2Opacity)
            .blendMode(.screen)

            // 4. Ring esplosivo — cerchio che si espande
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "00CFFF"), Color(hex: "FFFFFF"), Color(hex: "7B2FFF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: 200, height: 200)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
                .blur(radius: 2)
                .blendMode(.screen)

            // Ring secondo — leggermente dopo
            Circle()
                .stroke(Color(hex: "FFD700").opacity(0.6), lineWidth: 2)
                .frame(width: 260, height: 260)
                .scaleEffect(ringScale * 0.75)
                .opacity(ringOpacity * 0.7)
                .blur(radius: 3)
                .blendMode(.screen)

            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    let size = CGFloat(6 + (i % 3) * 3)
                    let angle = Double(i) * .pi / 6.0
                    let offsetX = CGFloat(cos(angle) * 140.0 * Double(sparkScale))
                    let offsetY = CGFloat(sin(angle) * 140.0 * Double(sparkScale))
                    let color = rayColors[i % rayColors.count]
                    
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                        .blur(radius: 2)
                        .offset(x: offsetX, y: offsetY)
                        .opacity(sparkOpacity)
                }
            }
            .blendMode(.screen)
        }
        .opacity(globalOpacity)
        .ignoresSafeArea()
        .onAppear { runAnimation() }
    }

    func runAnimation() {
        // Burst immediato
        withAnimation(.easeOut(duration: 0.25)) {
            burstScale = 2.2
            burstOpacity = 1.0
        }

        // Raggi appaiono veloci e ruotano
        withAnimation(.easeOut(duration: 0.15)) {
            rayOpacity = 1.0
            ray2Opacity = 0.8
            rayScale = 1.5
        }
        // Rotazione rapida layer 1
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rayRotation = 360
        }
        // Counter-rotazione layer 2
        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
            ray2Rotation = -360
        }

        // Ring esplode
        withAnimation(.easeOut(duration: 0.45)) {
            ringScale = 3.5
            ringOpacity = 0.9
        }

        // Scintille esplodono verso l'esterno
        withAnimation(.easeOut(duration: 0.4)) {
            sparkOpacity = 1.0
            sparkScale = 1.0
        }

        // Tutto inizia a sparire dopo 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.55)) {
                burstOpacity = 0
                rayOpacity = 0
                ray2Opacity = 0
                ringOpacity = 0
                sparkOpacity = 0
                globalOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
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
