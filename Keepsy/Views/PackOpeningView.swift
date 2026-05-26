import SwiftUI

// Identifiable wrapper used to drive fullScreenCover for album navigation
struct LocationContainer: Identifiable {
    let id = UUID()
    let name: String
}

// MARK: - Main Pack Opening View
struct PackOpeningView: View {
    @Binding var activeView: ContentView.ActiveView
    @StateObject private var locationManager = LocationManager()
    @State private var packState: PackState = .selecting

    @State private var cards: [ArtworkCard] = []
    @State private var showCards = false
    @State private var packTearOffset: CGFloat = 0
    @State private var packOpacity: Double = 1.0
    @State private var inspectedCard: ArtworkCard? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "06080B"), Color(hex: "14193B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            GridBackground()

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
                        SceneKitPacketView(onOpen: {
                            completeOpening()
                        })
                        .ignoresSafeArea()
                        .opacity(packState == .opened ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: packState)
                        .zIndex(10)
                    }

                    if packState == .opened {
                        VStack {
                            Spacer()
                            VStack(spacing: 20) {
                                HStack(spacing: 12) {
                                    ForEach(0..<min(3, cards.count), id: \.self) { index in
                                        CardView(card: $cards[index]) {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                inspectedCard = cards[index]
                                            }
                                        }
                                        .offset(
                                            x: showCards ? 0 : (index == 0 ? 123 : (index == 2 ? -123 : 0)),
                                            y: showCards ? 0 : 94
                                        )
                                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showCards)
                                    }
                                }
                                HStack(spacing: 12) {
                                    ForEach(3..<min(5, cards.count), id: \.self) { index in
                                        CardView(card: $cards[index]) {
                                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                                inspectedCard = cards[index]
                                            }
                                        }
                                        .offset(
                                            x: showCards ? 0 : (index == 3 ? 61.5 : -61.5),
                                            y: showCards ? 0 : -94
                                        )
                                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showCards)
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

            if let card = inspectedCard {
                CardInspectionView(card: card) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        self.inspectedCard = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .zIndex(100)
            }
        }
        .onAppear {
            loadActivePack()
        }
    }

    func completeOpening() {
        let artworks = CardDatabase.artworksFor(location: locationManager.currentCity).shuffled()
        let selectedArtworks = Array(artworks.prefix(5))
        self.cards = selectedArtworks.map {
            ArtworkCard(name: $0, imageName: $0, gradient: CardDatabase.gradientFor(name: $0), isFlipped: false)
        }
        CardDatabase.addFoundCards(selectedArtworks)
        UserDefaults.standard.set(selectedArtworks, forKey: "activePackCards")
        
        packState = .opened
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            showCards = true
        }
    }

    func loadActivePack() {
        if CardDatabase.hasActivePack() {
            let activeNames = CardDatabase.getActivePack() ?? []
            self.cards = activeNames.map { name in
                ArtworkCard(name: name, imageName: name, gradient: CardDatabase.gradientFor(name: name), isFlipped: true)
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
    }
}

// MARK: - Single Continuous Scroll View
struct SingleScrollPackView: View {
    let currentCity: String
    let onStart: () -> Void
    let onTapActivePack: () -> Void

    @State private var foundCards: Set<String> = []
    @State private var revealedCards: Set<String> = []
    @State private var activeLocation: LocationContainer? = nil

    var hasPixelatedCapodimonteCards: Bool {
        let capodimonteArtworks = CardDatabase.artworksFor(location: currentCity)
        return capodimonteArtworks.contains { name in
            foundCards.contains(name) && !revealedCards.contains(name)
        }
    }

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

                // ── SECTION 1: Pack ──────────────────────────────────
                VStack(spacing: 0) {
                    // Location badge
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.8), Color(white: 0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
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
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.18), Color(white: 0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.top, 105)
                    .padding(.bottom, 30)

                    if CardDatabase.hasActivePack(), let activePack = CardDatabase.getActivePack(), !activePack.isEmpty {
                        let firstCardName = activePack[0]
                        let isFirstCardRevealed = revealedCards.contains(firstCardName)
                        
                        // Torn center pack showing first card
                        ZStack(alignment: .center) {
                            SceneKitPacketView(
                                interactive: false,
                                isTorn: true,
                                firstCardName: firstCardName,
                                isFirstCardRevealed: isFirstCardRevealed,
                                tearMaskImage: loadSavedTearMask()
                            )
                            .frame(width: 310, height: 457)
                            .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        }
                        .frame(width: 310, height: 400)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTapActivePack()
                        }
                        .padding(.bottom, 24)

                        // VEDI CARTE button
                        Button(action: {
                            onTapActivePack()
                        }) {
                            Text("VEDI CARTE")
                                .font(.system(size: 16, weight: .black))
                                .italic()
                                .foregroundColor(.black)
                                .frame(width: 160, height: 44)
                                .background(
                                    Capsule()
                                        .fill(Color.orange)
                                        .shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4)
                                )
                        }
                        .padding(.bottom, 40)
                    } else {
                        // Roulette: 3 packs
                        ZStack {
                            // Ghost left
                            SceneKitPacketView(interactive: false)
                                .frame(width: 170, height: 250)
                                .opacity(0.4)
                                .scaleEffect(0.82)
                                .rotation3DEffect(.degrees(28), axis: (x: 0, y: 1, z: 0))
                                .offset(x: -200, y: 10)

                            // Ghost right
                            SceneKitPacketView(interactive: false)
                                .frame(width: 170, height: 250)
                                .opacity(0.4)
                                .scaleEffect(0.82)
                                .rotation3DEffect(.degrees(-28), axis: (x: 0, y: 1, z: 0))
                                .offset(x: 200, y: 10)

                            // Center pack
                            SceneKitPacketView(interactive: false)
                                .frame(width: 310, height: 457)
                                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        }
                        .frame(height: 400)
                        .padding(.bottom, 24)

                        // START button
                        Button(action: {
                            onStart()
                        }) {
                            Text("START")
                                .font(.system(size: 16, weight: .black))
                                .italic()
                                .foregroundColor(.black)
                                .frame(width: 134, height: 44)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "D8D8D8"))
                                        .shadow(color: .black.opacity(0.5), radius: 39, x: 0, y: 4)
                                )
                        }
                        .padding(.bottom, 40)
                    }
                }

                // ── SECTION 2: Expansions rows ───────────────────────
                VStack(spacing: 14) {
                    ForEach(expansions.indices, id: \.self) { idx in
                        let item = expansions[idx]
                        let info = progressFor(item.location, title: item.title)
                        PackExpansionRow(
                            progress: info.progress,
                            onTap: { activeLocation = LocationContainer(name: item.location) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
        }
        .fullScreenCover(item: $activeLocation) { container in
            CollectionAlbumView(museumLocation: container.name, showCloseButton: true) {
                activeLocation = nil
            }
        }
    }

    var visibleExpansions: [(location: String, title: String)] {
        expansions
    }

    func progressFor(_ location: String, title: String) -> (progress: Double, found: Int, total: Int) {
        let artworks = CardDatabase.artworksFor(location: "NAPLES")
        let found = artworks.filter { revealedCards.contains($0) }.count
        return (artworks.isEmpty ? 0 : Double(found) / Double(artworks.count), found, artworks.count)
    }
}

// MARK: - Expansion Row
struct PackExpansionRow: View {
    let progress: Double
    let onTap: () -> Void

    var isComplete: Bool { progress >= 1.0 }
    var percentText: String { "\(Int(round(progress * 100)))%" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Pack images (left)
                ZStack {
                    SceneKitPacketView(interactive: false)
                        .frame(width: 105, height: 155)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -8, y: 15)
                    SceneKitPacketView(interactive: false)
                        .frame(width: 105, height: 155)
                        .rotationEffect(.degrees(10))
                        .offset(x: 24, y: 0)
                }
                .frame(width: 170, height: 170)
                .clipped()

                Spacer()

                // Percentage + progress bar + chevron (right)
                VStack(alignment: .trailing, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))

                    Spacer()

                    Text(percentText)
                        .font(.system(size: 34, design: .monospaced))
                        .bold()
                        .italic()
                        .foregroundColor(.white)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 5)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(6, 140 * CGFloat(progress)), height: 5)
                    }
                    .frame(width: 140, height: 5)
                }
                .padding(.vertical, 24)
                .padding(.trailing, 24)
            }
            .frame(width: 344, height: 194)
            .background(
                Group {
                    if isComplete {
                        LinearGradient(
                            colors: [Color(hex: "F1B40A"), Color(hex: "E55812")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    } else {
                        Color(white: 0.12)
                    }
                }
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isComplete ?
                            LinearGradient(colors: [Color(hex: "F2CA03"), Color(hex: "C7A245")], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color(hex: "B1B1B1"), Color(hex: "B1B1B1").opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct PackOpeningView_Previews: PreviewProvider {
    static var previews: some View {
        PackOpeningView(activeView: .constant(.opening))
    }
}
