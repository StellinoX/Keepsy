import SwiftUI

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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(museum.name) pack, in progress")
                        .accessibilityHint("Double-tap to continue opening pack")
                        .accessibilityAddTraits(.isButton)
                } else {
                    SceneKitPacketView(interactive: false, isTorn: false,
                                       museumId: museum.id,
                                       packetImageName: packetImage)
                        .frame(width: 380, height: 515)
                        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 15)
                        .contentShape(Rectangle())
                        .onTapGesture { onTapStart() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(isComplete ? "\(museum.name) pack, collection complete" : "\(museum.name) card pack")
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
            if let data = UserDefaults.standard.data(forKey: "activePackTearMask_\(museum.id)")
                ?? UserDefaults.standard.data(forKey: "activePackTearMask") {
                savedTearMask = UIImage(data: data)
            }
        }
    }
}
