import SwiftUI

struct LocationContainer: Identifiable {
    let id = UUID()
    let name: String
}

struct PackOpeningView: View {
    @Binding var activeView: ContentView.ActiveView
    @StateObject private var locationManager = LocationManager()
    @State private var packState: PackState = .selecting

    @State private var cards: [ArtworkCard] = []
    @State private var showCards = false
    @State private var packTearOffset: CGFloat = 0
    @State private var packOpacity: Double = 1.0
    @State private var inspectedCard: ArtworkCard? = nil
    @State private var hasSyncedWithCloud = false
    @State private var flashOpacity: Double = 0.0
    @State private var showOpeningEffect = false

    // Animazione carte — una per carta
    @State private var cardOffsetY: [CGFloat] = Array(repeating: -800, count: 5)
    @State private var cardScale: [CGFloat] = Array(repeating: 0.6, count: 5)
    @State private var cardOpacity: [Double] = Array(repeating: 0, count: 5)
    @State private var cardBlur: [CGFloat] = Array(repeating: 12, count: 5)

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
                                        CardView(card: $cards[index]) {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                inspectedCard = cards[index]
                                            }
                                        }
                                        .offset(y: cardOffsetY[index])
                                        .scaleEffect(cardScale[index])
                                        .opacity(cardOpacity[index])
                                        .blur(radius: cardBlur[index])
                                    }
                                }
                                // Riga 2: carte 3,4
                                HStack(spacing: 12) {
                                    ForEach(3..<min(5, cards.count), id: \.self) { index in
                                        CardView(card: $cards[index]) {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                inspectedCard = cards[index]
                                            }
                                        }
                                        .offset(y: cardOffsetY[index])
                                        .scaleEffect(cardScale[index])
                                        .opacity(cardOpacity[index])
                                        .blur(radius: cardBlur[index])
                                    }
                                }
                            }
                            Spacer()
                            if cards.allSatisfy({ $0.isFlipped }) {
                                Button(action: {
                                    resetPack()
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        activeView = .arScanner
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
        .onChange(of: hasSyncedWithCloud) { synced in
            if synced && packState == .opened { loadActivePack() }
        }
        .onAppear {
            loadActivePack()
        }
    }

    // MARK: - Animazione ingresso carte

    func animateCardsIn() {
        // Ogni carta piomba dall'alto con delay sfalsato
        // Le prime tre (riga 1) arrivano quasi insieme, poi le ultime due
        let delays: [Double] = [0.0, 0.08, 0.16, 0.10, 0.18]

        for index in 0..<min(5, cards.count) {
            // Stato iniziale: sopra lo schermo, sfocata, invisibile
            cardOffsetY[index] = -700
            cardScale[index] = 0.75
            cardOpacity[index] = 0
            cardBlur[index] = 16

            DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) {
                // Appare e piomba giù veloce
                withAnimation(.easeIn(duration: 0.18)) {
                    cardOffsetY[index] = 18   // quasi arrivata, appena oltre
                    cardOpacity[index] = 1.0
                    cardBlur[index] = 0
                    cardScale[index] = 1.04
                }

                // Impatto: haptic + rimbalzo spring
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    HapticManager.shared.triggerImpact(style: .rigid)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) {
                        cardOffsetY[index] = 0
                        cardScale[index] = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Logic

    func completeOpening() {
        let artworks = CardDatabase.artworksFor(location: locationManager.currentCity).shuffled()
        let selectedArtworks = Array(artworks.prefix(5))
        
        self.cards = selectedArtworks.map {
            ArtworkCard(
                name: $0,
                imageName: $0,
                gradient: CardDatabase.gradientFor(name: $0),
                isFlipped: false
            )
        }
        CardDatabase.addFoundCards(selectedArtworks)
        UserDefaults.standard.set(selectedArtworks, forKey: "activePackCards")
        self.packState = .opened
        self.showCards = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            animateCardsIn()
        }
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
                cardOffsetY[i] = 0
                cardScale[i] = 1.0
                cardOpacity[i] = 1.0
                cardBlur[i] = 0
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
        for i in 0..<5 {
            cardOffsetY[i] = -800
            cardScale[i] = 0.6
            cardOpacity[i] = 0
            cardBlur[i] = 12
        }
    }
}

// MARK: - SingleScrollPackView, PackExpansionRow, LightBeamView
// (invariati rispetto all'originale)

struct SingleScrollPackView: View {
    let currentCity: String
    let onStart: () -> Void
    let onTapActivePack: () -> Void

    @State private var foundCards: Set<String> = []
    @State private var revealedCards: Set<String> = []
    @State private var activeLocation: LocationContainer? = nil

    func loadSavedTearMask() -> UIImage? {
        if let data = UserDefaults.standard.data(forKey: "activePackTearMask") {
            return UIImage(data: data)
        }
        return nil
    }

    let expansions: [(location: String, title: String)] = [
        ("FULL_COLLECTION", "Capodimonte")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
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
                    .padding(.top, 105)
                    .padding(.bottom, 30)

                    if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                        let firstCardName = activePack[0]
                        let isFirstCardRevealed = revealedCards.contains(firstCardName)

                        ZStack(alignment: .center) {
                            SceneKitPacketView(interactive: false, isTorn: true, firstCardName: firstCardName, isFirstCardRevealed: isFirstCardRevealed, tearMaskImage: loadSavedTearMask())
                                .frame(width: 310, height: 457)
                                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        }
                        .frame(width: 310, height: 400)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapActivePack() }
                        .padding(.bottom, 24)

                        Button(action: { onTapActivePack() }) {
                            Text("VEDI CARTE")
                                .font(.system(size: 16, weight: .black)).italic()
                                .foregroundColor(.black)
                                .frame(width: 160, height: 44)
                                .background(Capsule().fill(Color.orange).shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4))
                        }
                        .padding(.bottom, 40)
                    } else {
                        ZStack {
                            SceneKitPacketView(interactive: false)
                                .frame(width: 170, height: 250).opacity(0.4).scaleEffect(0.82)
                                .rotation3DEffect(.degrees(28), axis: (x: 0, y: 1, z: 0)).offset(x: -200, y: 10)
                            SceneKitPacketView(interactive: false)
                                .frame(width: 170, height: 250).opacity(0.4).scaleEffect(0.82)
                                .rotation3DEffect(.degrees(-28), axis: (x: 0, y: 1, z: 0)).offset(x: 200, y: 10)
                            SceneKitPacketView(interactive: false)
                                .frame(width: 310, height: 457)
                                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        }
                        .frame(height: 400).padding(.bottom, 24)

                        Button(action: { onStart() }) {
                            Text("START")
                                .font(.system(size: 16, weight: .black)).italic()
                                .foregroundColor(.black)
                                .frame(width: 134, height: 44)
                                .background(Capsule().fill(Color(hex: "D8D8D8")).shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4))
                        }
                        .padding(.bottom, 40)
                    }
                }

                VStack(spacing: 14) {
                    ForEach(expansions.indices, id: \.self) { idx in
                        let item = expansions[idx]
                        let info = progressFor(item.location, title: item.title)
                        PackExpansionRow(progress: info.progress, onTap: { activeLocation = LocationContainer(name: item.location) })
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
        }
        .fullScreenCover(item: $activeLocation) { container in
            CollectionAlbumView(museumLocation: container.name, showCloseButton: true) { activeLocation = nil }
        }
    }

    func progressFor(_ location: String, title: String) -> (progress: Double, found: Int, total: Int) {
        let artworks = CardDatabase.artworksFor(location: "NAPLES")
        let found = artworks.filter { revealedCards.contains($0) }.count
        return (artworks.isEmpty ? 0 : Double(found) / Double(artworks.count), found, artworks.count)
    }
}

struct PackExpansionRow: View {
    let progress: Double
    let onTap: () -> Void
    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                ZStack {
                    SceneKitPacketView(interactive: false).frame(width: 105, height: 155).rotationEffect(.degrees(-12)).offset(x: -8, y: 15)
                    SceneKitPacketView(interactive: false).frame(width: 105, height: 155).rotationEffect(.degrees(10)).offset(x: 24, y: 0)
                }
                .frame(width: 170, height: 170).clipped()
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.45))
                    Spacer()
                    Text(percentText).font(.system(size: 34, design: .monospaced)).bold().italic().foregroundColor(.white)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22)).frame(height: 5)
                        Capsule().fill(Color.white).frame(width: max(6, 140 * CGFloat(progress)), height: 5)
                    }.frame(width: 140, height: 5)
                }
                .padding(.vertical, 24).padding(.trailing, 24)
            }
            .frame(width: 344, height: 194)
            .background(Group {
                if isComplete {
                    LinearGradient(colors: [Color(hex: "F1B40A"), Color(hex: "E55812")], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else { Color(white: 0.12) }
            })
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                isComplete ?
                    LinearGradient(colors: [Color(hex: "F2CA03"), Color(hex: "C7A245")], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [Color(hex: "B1B1B1"), Color(hex: "B1B1B1").opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
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

            // 5. Scintille — 12 punti luminosi che esplodono
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    Circle()
                        .fill(rayColors[i % rayColors.count])
                        .frame(width: 6 + CGFloat(i % 3) * 3, height: 6 + CGFloat(i % 3) * 3)
                        .blur(radius: 2)
                        .offset(
                            x: cos(Double(i) * .pi / 6) * 140 * Double(sparkScale),
                            y: sin(Double(i) * .pi / 6) * 140 * Double(sparkScale)
                        )
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
