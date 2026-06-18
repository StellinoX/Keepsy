import SwiftUI

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
                    .onTapGesture { onTapCity() }
                    .padding(.bottom, 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Location: \(displayedCity)")
                    .accessibilityHint("Double-tap to change museum")
                    .accessibilityAddTraits(.isButton)

                ZStack {
                    ForEach(Array(museums.enumerated()), id: \.element.id) { index, museum in
                        let diff = circularDifference(index: index, scrollPosition: scrollPosition, count: museums.count)
                        let absDiff = abs(diff)
                        let scale: CGFloat = 1.25 - min(absDiff, 1.0) * (1.25 - 0.88)
                        let opacity: Double = {
                            if absDiff > 1.1 { return 0.0 }
                            else if absDiff <= 1.0 { return 1.0 - absDiff * (1.0 - 0.65) }
                            else { return 0.65 * (1.0 - (absDiff - 1.0) / 0.1) }
                        }()
                        let rotation: Double = {
                            let maxRot: Double = 5.0
                            if diff > 1.0 { return maxRot }
                            else if diff < -1.0 { return -maxRot }
                            else { return Double(diff) * maxRot }
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

                let isSelectedActive = CardDatabase.hasActivePack(for: selectedMuseumId)
                Button(action: isSelectedActive ? onTapActivePack : onStart) {
                    Text(isSelectedActive ? "CONTINUE" : "START")
                        .font(.custom("Helvetica-BoldOblique", size: 18))
                        .foregroundColor(.black)
                        .frame(width: 134, height: 44)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.white, Color(hex: "EAEAEA")],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .shadow(color: .black.opacity(0.55), radius: 39, x: 0, y: 4)
                        )
                }
                .padding(.top, 25)
                .padding(.bottom, 36)
                .accessibilityLabel(isSelectedActive ? "Continue pack" : "Start new pack")
                .accessibilityHint(isSelectedActive ? "Returns to cards in active pack" : "Opens a new card pack from \(displayedCity)")

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
        if diff > half { diff -= c }
        else if diff <= -half { diff += c }
        return diff
    }
}
