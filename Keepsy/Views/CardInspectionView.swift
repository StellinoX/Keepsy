import SwiftUI

struct CardInspectionView: View {
    let card: ArtworkCard
    var namespace: Namespace.ID? = nil
    var isZoomingFromAlbum: Bool = false
    var externalScale: CGFloat = 1.0
    var externalOpacity: Double = 1.0
    let onClose: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedRotation: Double = 0.0
    @State private var animateContent: Bool = false
    @State private var animateSheet: Bool = false
    @State private var sheetOffset: CGFloat = 0
    @State private var verticalDragOffset: CGFloat = 0

    enum SheetState {
        case collapsed
        case expanded
    }
    @State private var sheetState: SheetState = .collapsed
    @State private var miniSheetDrag: CGFloat = 0
    @State private var showFullDetail: Bool = false

    private func isCollectionCompleteFor(_ cardName: String) -> Bool {
        if cardName == "vale" {
            let artworks = CardDatabase.artworksFor(location: "moma")
            let revealed = CardDatabase.getRevealedCards()
            return !artworks.isEmpty && artworks.allSatisfy { revealed.contains($0) }
        }
        guard cardName.contains("_experience") else { return true }
        let location = cardName.replacingOccurrences(of: "_experience", with: "")
        let artworks = CardDatabase.artworksFor(location: location)
        let revealed = CardDatabase.getRevealedCards()
        return !artworks.isEmpty && artworks.allSatisfy { revealed.contains($0) }
    }

    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(card.name) || card.name.contains("_experience") || card.name == "vale"
    }

    private var artwork: NetworkArtwork? {
        CardDatabase.remoteArtworks[card.name]
    }

    private var categoryName: String {
        if card.name.contains("_experience") || card.name == "vale" { return "EXPERIENCE" }
        guard let artist = artwork?.artist else { return "Collection" }
        let artistLower = artist.lowercased()
        if artistLower.contains("degas") || artistLower.contains("manet") || artistLower.contains("monet") || artistLower.contains("renoir") {
            return "Impressionism"
        } else if artistLower.contains("caravaggio") || artistLower.contains("ribera") || artistLower.contains("giordano") || artistLower.contains("solimena") {
            return "Baroque"
        } else if artistLower.contains("tiziano") || artistLower.contains("raffaello") || artistLower.contains("michelangelo") || artistLower.contains("bellini") || artistLower.contains("parmigianino") {
            return "Renaissance"
        }
        return "Classical Art"
    }

    private var artistName: String {
        if card.name.contains("_experience") || card.name == "vale" {
            if !isCollectionCompleteFor(card.name) { return "Locked" }
            return "Keepsy Collection"
        }
        return artwork?.artist ?? "Unknown Artist"
    }

    private var creationYear: String {
        if card.name.contains("_experience") || card.name == "vale" {
            if !isCollectionCompleteFor(card.name) { return "????" }
            return "2026"
        }
        guard let raw = artwork?.createdAt else { return "Unknown Date" }
        if raw.contains("-") && raw.count > 10 { return String(raw.prefix(4)) }
        return raw
    }

    private var descriptionText: String {
        if card.name == "vale" {
            if !isCollectionCompleteFor(card.name) {
                return "To be unlocked when you have the whole collection"
            }
            return """
Hello! I'm Valentina, a 24 year old illustrator based in Naples, Italy.
I have been drawing ever since I have memory, I don't remember a moment where I didn't have a pencil, crayon or marker in hand. My love for art developed naturally from there.

Van Gogh is one of my favourite painters, and Starry Night one of his works I enjoy the most. I've seen it in person and I still remember how it moved me, so I'm particularly attached to it. It felt only natural to choose it. During my art school years I grew an interest in children illustration, and that's the style I wanted to reinterpret the painting in. Transposing a cornerstone of art into something much simpler, catered to a whole different public, was something unexpected but that I enjoyed immensely. I'd surely do it again if I'll ever have the possibility.
"""
        }
        if card.name.contains("_experience") {
            if !isCollectionCompleteFor(card.name) {
                return "To be unlocked when you have the whole collection"
            }
            return "Congratulations! You have completed the entire museum collection and unlocked this exclusive Keepsy Experience Card. You've proven yourself a true art connoisseur!"
        }
        return artwork?.description ?? "No description available for this artwork"
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let cardWidth: CGFloat = 310
            let cardHeight: CGFloat = 470

            ZStack {
                if isZoomingFromAlbum {
                    // Album mode background
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeAction() }

                    if showFullDetail {
                        CardFullDetailView(
                            card: card,
                            namespace: namespace,
                            onClose: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    showFullDetail = false
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        let cardW: CGFloat = min(geometry.size.width - 48, 300)
                        let cardH: CGFloat = cardW * (470.0 / 310.0)
                        let sheetPeekHeight: CGFloat = 160
                        let cardTopY: CGFloat = max(140, (screenHeight - cardH - sheetPeekHeight) / 2 + 10)

                        let index = CardDatabase.allArtworkNames.firstIndex(of: card.name)
                        let goldBorder = LinearGradient(
                            colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"),
                                     Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )

                        if (card.name.contains("_experience") || card.name == "vale") && !isCollectionCompleteFor(card.name) {
                            Group {
                                if card.name == "vale" {
                                    Image("dasbloccare")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(LinearGradient(
                                                colors: [Color(hex: "5168C4"), Color(hex: "3F53B3")],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ))
                                        Text("?")
                                            .font(.system(size: 110, weight: .black))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .frame(width: cardW, height: cardH)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: Color(hex: "5168C4").opacity(0.4), radius: 30, x: 0, y: 15)
                            .scaleEffect(sheetState == .expanded ? 0.85 : 1.0)
                            .position(x: geometry.size.width / 2, y: cardTopY + cardH / 2)
                            .offset(y: sheetState == .expanded ? -30 : 0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: sheetState)
                        } else {
                            ArtworkCardFrontView(
                                name: card.name,
                                title: card.title,
                                cardIndex: index,
                                width: cardW,
                                height: cardH,
                                isRevealed: isRevealed,
                                goldBorder: goldBorder
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.triggerImpact(style: .medium)
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    showFullDetail = true
                                }
                            }
                            .position(x: geometry.size.width / 2, y: cardTopY + cardH / 2)
                            .scaleEffect(sheetState == .expanded ? 0.85 : 1.0)
                            .offset(y: sheetState == .expanded ? -30 : 0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: sheetState)
                            .opacity(1.0)
                        }

                        // Mini-sheet
                        let collapsedY = screenHeight - sheetPeekHeight
                        let expandedY  = screenHeight * 0.42
                        let sheetY: CGFloat = {
                            switch sheetState {
                            case .collapsed: return collapsedY
                            case .expanded:  return expandedY
                            }
                        }()
                        let sheetHeight: CGFloat = screenHeight * 0.90

                        VStack(spacing: 0) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 36, height: 5)
                                .padding(.top, 12)
                                .padding(.bottom, 18)

                            VStack(alignment: .leading, spacing: 14) {
                                Text(categoryName.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))

                                Text((card.name.contains("_experience") || card.name == "vale") && !isCollectionCompleteFor(card.name) ? "Locked Experience" : card.title)
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundColor(.white)
                                    .lineLimit(3)

                                Text("\(artistName); \(creationYear)")
                                    .font(.system(size: 15).italic())
                                    .foregroundColor(.white.opacity(0.65))

                                Color.white.opacity(0.1).frame(height: 1).padding(.vertical, 4)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 10)

                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(descriptionText)
                                        .font(.system(size: 15))
                                        .foregroundColor(Color(hex: "D1D1D6"))
                                        .lineSpacing(4)
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                            }
                            .scrollDisabled(sheetState != .expanded)
                        }
                        .frame(width: geometry.size.width, height: sheetHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color(white: 0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [Color.white, Color(hex: "B1B1B1")],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ), lineWidth: 1.5
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: -4)
                        .position(x: geometry.size.width / 2, y: sheetY + miniSheetDrag + sheetHeight / 2)
                        .offset(y: 0)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    miniSheetDrag = min(max(v.translation.height, -200), 200)
                                }
                                .onEnded { v in
                                    let drag = v.translation.height
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                        miniSheetDrag = 0
                                        if drag < -40 {
                                            sheetState = .expanded
                                        } else if drag > 40 {
                                            if sheetState == .expanded {
                                                sheetState = .collapsed
                                            } else {
                                                closeAction()
                                            }
                                        }
                                    }
                                }
                        )
                    }

                } else {
                    // ── MODALITÀ BUSTINA ────────────────────────────────────────

                    // Sfondo scuro — tap fuori dalla carta chiude
                    Color.black
                        .opacity(0.85)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture { closeAction() }

                    // Carta con effetto metallico
                    SilverMetalCardView(
                        width: cardWidth,
                        height: cardHeight,
                        isEnabled: isFrontShowing,
                        tiltX: Double(dragOffset.width) / (cardWidth / 2.0),
                        tiltY: Double(dragOffset.height) / (cardHeight / 2.0),
                        customRotationX: Double(-dragOffset.height) / 10.0,
                        customRotationY: currentRotation
                    ) {
                        ZStack {
                            Image("retro")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))

                            let index = CardDatabase.allArtworkNames.firstIndex(of: card.name)
                            let goldBorder = LinearGradient(
                                colors: [
                                    Color(hex: "F5E480"), Color(hex: "F1B40A"),
                                    Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )

                            ArtworkCardFrontView(
                                name: card.name,
                                title: card.title,
                                cardIndex: index,
                                width: 310,
                                height: 470,
                                isRevealed: isRevealed,
                                goldBorder: goldBorder
                            )
                            .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
                        }
                    }
                    .matchedGeometryEffectOptional(id: "card_\(card.name)", in: isZoomingFromAlbum ? nil : namespace, isSource: false)
                    .offset(y: isZoomingFromAlbum ? -50 : 0)
                    .scaleEffect(1.0)
                    .opacity(1.0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        SoundManager.shared.playSound(named: "giro_carta")
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                            accumulatedRotation += 180
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in dragOffset = value.translation }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                    if value.translation.width > 80 {
                                        SoundManager.shared.playSound(named: "giro_carta")
                                        accumulatedRotation += 180
                                    } else if value.translation.width < -80 {
                                        SoundManager.shared.playSound(named: "giro_carta")
                                        accumulatedRotation -= 180
                                    }
                                    dragOffset = .zero
                                }
                            }
                    )
                }
            }
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                if isZoomingFromAlbum {
                    animateContent = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            animateSheet = true
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                        animateContent = true
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func closeAction() {
        HapticManager.shared.triggerImpact(style: .light)
        sheetState = .collapsed
        if isZoomingFromAlbum {
            onClose()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                animateContent = false
            }
            onClose()
        }
    }

    private var isFrontShowing: Bool {
        let absRot = abs(currentRotation.truncatingRemainder(dividingBy: 360))
        return !(absRot > 90 && absRot < 270)
    }

    private var currentRotation: Double {
        let dragRotation = Double(dragOffset.width) / 4.0
        return accumulatedRotation + dragRotation
    }
}

// MARK: - CardFullDetailView

struct CardFullDetailView: View {
    let card: ArtworkCard
    var namespace: Namespace.ID? = nil
    let onClose: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedRotation: Double = 0.0
    @State private var animateContent: Bool = false

    private let cardWidth: CGFloat = 310
    private var cardHeight: CGFloat { 470 }

    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(card.name) || card.name.contains("_experience") || card.name == "vale"
    }

    private var isFrontShowing: Bool {
        let absRot = abs(currentRotation.truncatingRemainder(dividingBy: 360))
        return !(absRot > 90 && absRot < 270)
    }

    private var currentRotation: Double {
        accumulatedRotation + Double(dragOffset.width) / 4.0
    }

    var body: some View {
        ZStack {
            Color.black.opacity(animateContent ? 0.88 : 0.0)
                .ignoresSafeArea()
                .onTapGesture { closeDetail() }

            SilverMetalCardView(
                width: cardWidth, height: cardHeight,
                isEnabled: isFrontShowing,
                tiltX: Double(dragOffset.width) / (cardWidth / 2.0),
                tiltY: Double(dragOffset.height) / (cardHeight / 2.0),
                customRotationX: Double(-dragOffset.height) / 10.0,
                customRotationY: currentRotation
            ) {
                ZStack {
                    Image("retro")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))

                    let index = CardDatabase.allArtworkNames.firstIndex(of: card.name)
                    let goldBorder = LinearGradient(
                        colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    ArtworkCardFrontView(
                        name: card.name,
                        title: card.title,
                        cardIndex: index,
                        width: 310,
                        height: 470,
                        isRevealed: isRevealed,
                        goldBorder: goldBorder
                    )
                    .opacity(isFrontShowing ? 1 : 0)
                }
            }
            .scaleEffect(animateContent ? 1.0 : 0.85)
            .opacity(animateContent ? 1.0 : 0.0)
            .contentShape(Rectangle())
            .onTapGesture {
                SoundManager.shared.playSound(named: "giro_carta")
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    accumulatedRotation += 180
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { v in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            if v.translation.width > 80 {
                                SoundManager.shared.playSound(named: "giro_carta")
                                accumulatedRotation += 180
                            } else if v.translation.width < -80 {
                                SoundManager.shared.playSound(named: "giro_carta")
                                accumulatedRotation -= 180
                            }
                            dragOffset = .zero
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { animateContent = true }
        }
    }

    private func closeDetail() {
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.easeOut(duration: 0.22)) { animateContent = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onClose() }
    }
}

fileprivate extension View {
    @ViewBuilder
    func matchedGeometryEffectOptional<ID: Hashable>(id: ID, in namespace: Namespace.ID?, isSource: Bool = true) -> some View {
        if let namespace = namespace {
            self.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}
