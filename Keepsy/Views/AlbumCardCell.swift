import SwiftUI

struct AlbumCardCell: View {
    let name: String
    let index: Int
    let isFound: Bool
    let isRevealed: Bool
    let hasSynced: Bool
    let cardOpacity: Double
    let isAnimating: Bool
    let hidePocket: Bool

    var body: some View {
        ZStack {
            if isFound {
                ZStack(alignment: .top) {
                    let borderGrad = CardDatabase.borderGradientFor(name: name)
                    ArtworkCardFrontView(
                        name: name,
                        title: CardDatabase.remoteArtworks[name]?.title ?? CardDatabase.cleanedArtworkName(name),
                        cardIndex: index,
                        width: 58,
                        height: 84,
                        isRevealed: isRevealed,
                        goldBorder: borderGrad
                    )
                    .opacity(cardOpacity)

                    if !(isAnimating && hidePocket) {
                        Image("pocket_outline")
                            .resizable()
                            .frame(width: 72, height: 94)
                            .padding(.top, 5)
                    }
                }
                .frame(width: 72, height: 103)

            } else {
                ZStack(alignment: .top) {
                    ZStack(alignment: .center) {
                        Text(String(format: "%02d", index + 1))
                            .font(.custom("Helvetica-BoldOblique", size: 17))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "000000"), Color(hex: "6F6F6F")],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
                            .padding(.top, 4)

                        if !isAnimating {
                            Image("pocket_outline")
                                .resizable()
                        }
                    }
                    .frame(width: 72, height: 94)
                    .padding(.top, 5)
                }
                .frame(width: 72, height: 103)
            }
        }
    }
}
