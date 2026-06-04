import SwiftUI

struct CardView: View {
    @Binding var card: ArtworkCard
    var cardIndex: Int? = nil
    var onInspect: (() -> Void)? = nil

    @State private var rotation: Double = 0

    // Dimensioni originali — NON modificare
    private let w: CGFloat = 111
    private let h: CGFloat = 168
    private let cr: CGFloat = 3

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
        // Frame + clip + shadow condivisi → fronte e retro identici
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: cr))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
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
        Image("retro")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: w, height: h)
            .clipped()
    }

    private var cardFront: some View {
        let isRevealed = CardDatabase.getRevealedCards().contains(card.name)
        let isAlreadyOwned = CardDatabase.getDuplicatesInActivePack().contains(card.name)
        return ArtworkCardFrontView(
            name: card.name,
            title: card.title,
            cardIndex: cardIndex,
            width: w,
            height: h,
            isRevealed: isRevealed,
            goldBorder: goldBorder,
            showCheckmark: isAlreadyOwned
        )
    }
}

// MARK: - Reusable Scalable Card Front
struct ArtworkCardFrontView: View {
    let name: String
    let title: String
    let cardIndex: Int?
    let width: CGFloat
    let height: CGFloat
    let isRevealed: Bool
    let goldBorder: LinearGradient
    var showCheckmark: Bool = false

    // Memberwise initializer to ensure default parameters work under all build circumstances
    init(
        name: String,
        title: String,
        cardIndex: Int?,
        width: CGFloat,
        height: CGFloat,
        isRevealed: Bool,
        goldBorder: LinearGradient,
        showCheckmark: Bool = false
    ) {
        self.name = name
        self.title = title
        self.cardIndex = cardIndex
        self.width = width
        self.height = height
        self.isRevealed = isRevealed
        self.goldBorder = goldBorder
        self.showCheckmark = showCheckmark
    }

    private var scale: CGFloat { width / 111.0 }
    private var cr: CGFloat { 3 * scale }
    private var artwork: NetworkArtwork? { CardDatabase.remoteArtworks[name] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. Full-bleed image
            ArtImageView(cardName: name, isRevealed: isRevealed)
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cr))

            // 2. Info Overlay (Title and Author/Year)
            VStack(alignment: .leading, spacing: 3 * scale) {
                // Title Box
                Text(title)
                    .font(.system(size: 5.5 * scale, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 3 * scale)
                    .frame(width: 105 * scale)
                    .frame(minHeight: 19 * scale, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 3 * scale)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 3 * scale).stroke(Color.black.opacity(0.12), lineWidth: 0.2 * scale))
                            .shadow(color: .black.opacity(0.35), radius: 14 * scale / 2.0, x: 0, y: -4 * scale / 2.0)
                    )

                // Author/Year Box
                let authorText = [artwork?.artist, artwork?.date]
                    .compactMap { v -> String? in
                        guard let s = v, !s.isEmpty else { return nil }
                        return s
                    }
                    .joined(separator: "; ")

                if !authorText.isEmpty {
                    Text(authorText)
                        .font(.system(size: 3.2 * scale).italic())
                        .foregroundColor(Color(white: 0.45))
                        .lineLimit(1)
                        .padding(.horizontal, 4 * scale)
                        .frame(height: 7 * scale)
                        .frame(minWidth: 40 * scale)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.2 * scale))
                                .shadow(color: .black.opacity(0.35), radius: 14 * scale / 2.0, x: 0, y: -4 * scale / 2.0)
                        )
                }
            }
            .padding(.leading, 3 * scale)
            .padding(.bottom, 4 * scale)

            // 3. Number Badge (Top Right)
            if let idx = cardIndex {
                VStack {
                    HStack {
                        Spacer()

                        let numStr = String(format: "%03d", idx + 1)
                        Text(numStr)
                            .font(.system(size: 4.2 * scale, weight: .black, design: .default).italic())
                            .overlay(
                                LinearGradient(
                                    colors: [Color(hex: "E36D13"), Color(hex: "FEBB0B")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .mask(
                                Text(numStr)
                                    .font(.system(size: 4.2 * scale, weight: .black, design: .default).italic())
                            )
                            .frame(width: 17 * scale, height: 7 * scale)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.3 * scale))
                                    .shadow(color: .black.opacity(0.87), radius: 3 * scale / 2.0, x: 0, y: 0)
                            )
                            .padding(.top, 3 * scale)
                            .padding(.trailing, 3 * scale)
                    }
                    Spacer()
                }
            }

            // 4. Checkmark Badge (Top Left)
            if showCheckmark {
                VStack {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .shadow(color: .black.opacity(0.35), radius: 2 * scale, x: 0, y: 1 * scale)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 11 * scale, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 20 * scale, height: 20 * scale)
                        .padding(.top, 6 * scale)
                        .padding(.leading, 6 * scale)
                        
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cr))
        // Nessuna shadow qui — gestita dal parent (CardView / SilverMetalCardView)
    }
}
