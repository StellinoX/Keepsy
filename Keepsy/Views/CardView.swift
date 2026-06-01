import SwiftUI

struct CardView: View {
    @Binding var card: ArtworkCard
    var cardIndex: Int? = nil
    var onInspect: (() -> Void)? = nil

    @State private var rotation: Double = 0

    private let w: CGFloat = 111
    private let h: CGFloat = 168
    private let cr: CGFloat = 12  // w * 12/111

    private var goldBorder: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "F5E480"), Color(hex: "F1B40A"),
                Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var artwork: NetworkArtwork? { CardDatabase.remoteArtworks[card.name] }

    var body: some View {
        ZStack {
            cardBack
                .opacity(card.isFlipped ? 0 : 1)

            cardFront
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(card.isFlipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
        .onTapGesture {
            if !card.isFlipped {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    rotation += 180
                    card.isFlipped = true
                }
            } else {
                onInspect?()
            }
        }
        .onAppear {
            if card.isFlipped { rotation = 180 }
        }
    }

    // MARK: - Card Back (unrevealed)

    private var cardBack: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: cr)
                .fill(Color(hex: "1A0E6E"))

            Image("LogoKeepsy")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            RoundedRectangle(cornerRadius: cr)
                .stroke(goldBorder, lineWidth: 2)

            if let idx = cardIndex {
                badge(idx)
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
        }
        .frame(width: w, height: h)
    }

    // MARK: - Card Front (flipped / found)

    private var cardFront: some View {
        let imageH: CGFloat = 116
        let isRevealed = CardDatabase.getRevealedCards().contains(card.name)

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Artwork image
                ArtImageView(cardName: card.name, isRevealed: isRevealed)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w - 10, height: imageH)
                    .clipped()
                    .cornerRadius(cr - 2)
                    .padding(.top, 5)
                    .padding(.horizontal, 5)

                // Info strip
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let art = artwork {
                        let line = [art.artist, art.date]
                            .compactMap { v -> String? in
                                guard let s = v, !s.isEmpty else { return nil }
                                return s
                            }
                            .joined(separator: "; ")
                        if !line.isEmpty {
                            Text(line)
                                .font(.system(size: 6.5))
                                .foregroundColor(Color(white: 0.45))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: w, height: h, alignment: .top)
            .background(Color.white)
            .cornerRadius(cr)
            .overlay(RoundedRectangle(cornerRadius: cr).stroke(goldBorder, lineWidth: 2))

            if let idx = cardIndex {
                badge(idx)
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    // MARK: - Number Badge

    private func badge(_ index: Int) -> some View {
        Text(String(format: "%03d", index + 1))
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundColor(Color(hex: "1A0E6E"))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(hex: "F1B40A")))
    }
}
