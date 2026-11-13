import SwiftUI

struct MuseumPackPage: View {
    let pack: CarouselPack
    let revealedCards: Set<String>
    let isScrolling: Bool
    let onTapActivePack: () -> Void
    let onTapStart: () -> Void

    @State private var savedTearMask: UIImage? = nil

    private var activePack: [String]? {
        guard let cards = CardDatabase.getActivePack(for: pack.id),
              !cards.isEmpty else { return nil }
        return cards
    }

    private var isComplete: Bool {
        let artworks = CardDatabase.artworksFor(location: pack.id)
        return !artworks.isEmpty && artworks.allSatisfy { revealedCards.contains($0) }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let activePack = activePack {
                    let firstCardName = activePack[0]
                    SceneKitPacketView(interactive: false, isTorn: true,
                                       museumId: pack.id,
                                       packetImageName: pack.packetImageName,
                                       firstCardName: firstCardName,
                                       isFirstCardRevealed: revealedCards.contains(firstCardName),
                                       tearMaskImage: savedTearMask,
                                       isScrolling: isScrolling)
                        .frame(width: 380, height: 515)
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapActivePack() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(pack.name) pack, in progress")
                        .accessibilityHint("Double-tap to continue opening pack")
                        .accessibilityAddTraits(.isButton)
                } else {
                    SceneKitPacketView(interactive: false, isTorn: false,
                                       museumId: pack.id,
                                       packetImageName: pack.packetImageName,
                                       isScrolling: isScrolling)
                        .frame(width: 380, height: 515)
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapStart() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(isComplete ? "\(pack.name) pack, collection complete" : "\(pack.name) card pack")
                        .accessibilityHint(isComplete ? "" : "Double-tap to open pack")
                        .accessibilityAddTraits(isComplete ? .isStaticText : .isButton)
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
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            if let data = CardDatabase.activePackTearMask(for: pack.id) {
                savedTearMask = UIImage(data: data)
            }
        }
    }
}
