import SwiftUI
import CoreLocation

struct SingleScrollPackView: View {
    @Binding var activeView: ContentView.ActiveView
    let locationManager: LocationManager
    let currentCity: String
    @Binding var selectedMuseumId: String
    let onStart: () -> Void
    let onTapActivePack: () -> Void
    let onTapCity: () -> Void

    @State private var revealedCards: Set<String> = []

    private var packs: [CarouselPack] {
        locationManager.sortedMuseums(MuseumConfig.shared.museums).map { museum in
            CarouselPack(id: museum.id, name: museum.name, packetImageName: museum.packetImageName)
        } + [MuseumConfig.fareImpresa]
    }

    private func openAlbum(_ id: String) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            activeView = .collection(id)
        }
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
                        .foregroundStyle(.white)
                    Text("Keeper")
                        .font(.custom("Helvetica-BoldOblique", size: 38))
                        .foregroundStyle(.white)
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

                let isSelectedActive = CardDatabase.hasActivePack(for: selectedMuseumId)

                MuseumPackCarousel(
                    packs: packs,
                    revealedCards: revealedCards,
                    selectedMuseumId: $selectedMuseumId,
                    onTapActivePack: onTapActivePack,
                    onTapStart: onStart
                )
                .frame(height: 400)

                Button(action: isSelectedActive ? onTapActivePack : onStart) {
                    Text(isSelectedActive ? "CONTINUE" : "START")
                        .font(.custom("Helvetica-BoldOblique", size: 18))
                        .foregroundStyle(.black)
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
                .accessibilityHint(isSelectedActive ? "Returns to cards in active pack" : "Opens a new card pack")

                VStack(spacing: 14) {
                    ForEach(packs) { pack in
                        PackExpansionRow(
                            museumId: pack.id,
                            title: pack.name,
                            progress: progressFor(pack.id).progress,
                            onTap: { openAlbum(pack.id) }
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
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 20, height: 20)
            .padding(.leading, 6)

            Text(displayedCity)
                .font(.custom("Helvetica-BoldOblique", size: 11))
                .foregroundStyle(.white)
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

}
