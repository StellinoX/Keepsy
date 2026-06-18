import SwiftUI

enum CardAnimationPhase {
    case idle, pulling, zooming, open, closing
}

struct CellFramePreference: Equatable {
    let name: String
    let frame: CGRect
}

struct CellFramePreferenceKey: PreferenceKey {
    static var defaultValue: [CellFramePreference] = []
    static func reduce(value: inout [CellFramePreference], nextValue: () -> [CellFramePreference]) {
        value.append(contentsOf: nextValue())
    }
}

struct StickerGridView: View, Equatable {
    let artworks: [String]
    let foundCards: Set<String>
    let revealedCards: Set<String>
    let recentlyCompletedPack: [String]
    let animatedCompletedCards: Set<String>
    let hasSyncedWithCloud: Bool
    let animatingCardName: String?
    let cellCardOpacity: Double
    let animationPhase: CardAnimationPhase
    let hideCellPocket: Bool
    let frameTracker: FrameTracker
    let frameRefreshToken: Int
    let columns: [GridItem]
    let onTapCard: (String, CGRect) -> Void

    static func == (lhs: StickerGridView, rhs: StickerGridView) -> Bool {
        lhs.artworks == rhs.artworks &&
        lhs.foundCards == rhs.foundCards &&
        lhs.revealedCards == rhs.revealedCards &&
        lhs.recentlyCompletedPack == rhs.recentlyCompletedPack &&
        lhs.animatedCompletedCards == rhs.animatedCompletedCards &&
        lhs.hasSyncedWithCloud == rhs.hasSyncedWithCloud &&
        lhs.animatingCardName == rhs.animatingCardName &&
        lhs.cellCardOpacity == rhs.cellCardOpacity &&
        lhs.animationPhase == rhs.animationPhase &&
        lhs.hideCellPocket == rhs.hideCellPocket &&
        lhs.frameRefreshToken == rhs.frameRefreshToken
    }

    private func cellLabel(name: String, index: Int) -> String {
        let num = String(format: "%02d", index + 1)
        if revealedCards.contains(name) {
            let title = CardDatabase.remoteArtworks[name]?.title ?? CardDatabase.cleanedArtworkName(name)
            if let a = CardDatabase.remoteArtworks[name]?.artist, !a.isEmpty {
                return "Card \(num), \(title), by \(a)"
            }
            return "Card \(num), \(title)"
        } else if foundCards.contains(name) {
            return "Card \(num), found, scan to reveal"
        } else {
            return "Card \(num), not yet found"
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(artworks.enumerated()), id: \.offset) { index, name in
                let isInteractive = revealedCards.contains(name) && animationPhase == .idle
                AlbumCardCell(
                    name: name,
                    index: index,
                    isFound: revealedCards.contains(name) || recentlyCompletedPack.contains(name),
                    isRevealed: revealedCards.contains(name) && !recentlyCompletedPack.contains(name) ? true : animatedCompletedCards.contains(name),
                    hasSynced: hasSyncedWithCloud,
                    cardOpacity: (animatingCardName == name) ? cellCardOpacity : (recentlyCompletedPack.contains(name) && !animatedCompletedCards.contains(name) ? 0.0 : 1.0),
                    isAnimating: animatingCardName == name,
                    hidePocket: (animatingCardName == name) && hideCellPocket
                )
                .contentShape(Rectangle())
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CellFramePreferenceKey.self,
                            value: [CellFramePreference(name: name, frame: geo.frame(in: .named("root")))]
                        )
                    }
                )
                .onTapGesture {
                    guard recentlyCompletedPack.isEmpty else { return }
                    guard revealedCards.contains(name), animationPhase == .idle else { return }
                    if let f = frameTracker.cellFrames[name] {
                        onTapCard(name, f)
                    }
                }
                .frame(width: 72, height: 103)
                .id(name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cellLabel(name: name, index: index))
                .accessibilityAddTraits(isInteractive ? .isButton : .isStaticText)
                .accessibilityHint(isInteractive ? "Double-tap to view card details" : "")
            }
        }
        .onPreferenceChange(CellFramePreferenceKey.self) { preferences in
            for pref in preferences {
                frameTracker.cellFrames[pref.name] = pref.frame
            }
        }
    }
}
