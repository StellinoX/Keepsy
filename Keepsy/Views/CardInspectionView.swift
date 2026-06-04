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

    // Mini-sheet drag per album mode
    @State private var miniSheetExpanded: Bool = false
    @State private var miniSheetDrag: CGFloat = 0
    // Tap carta → dettaglio completo
    @State private var showFullDetail: Bool = false
    
    private func isCollectionCompleteFor(_ cardName: String) -> Bool {
        guard cardName.contains("_experience") else { return true }
        let location = cardName.replacingOccurrences(of: "_experience", with: "")
        let artworks = CardDatabase.artworksFor(location: location)
        let revealed = CardDatabase.getRevealedCards()
        return !artworks.isEmpty && artworks.allSatisfy { revealed.contains($0) }
    }

    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(card.name) || card.name.contains("_experience")
    }
    
    private var artwork: NetworkArtwork? {
        CardDatabase.remoteArtworks[card.name]
    }
    
    // Categorizzazione dinamica e intelligente dell'opera basata sull'artista
    private var categoryName: String {
        if card.name.contains("_experience") { return "ESPERIENZA" }
        guard let artist = artwork?.artist else { return "Collezione" }
        let artistLower = artist.lowercased()
        if artistLower.contains("degas") || artistLower.contains("manet") || artistLower.contains("monet") || artistLower.contains("renoir") {
            return "Impressionismo"
        } else if artistLower.contains("caravaggio") || artistLower.contains("ribera") || artistLower.contains("giordano") || artistLower.contains("solimena") {
            return "Barocco"
        } else if artistLower.contains("tiziano") || artistLower.contains("raffaello") || artistLower.contains("michelangelo") || artistLower.contains("bellini") || artistLower.contains("parmigianino") {
            return "Rinascimento"
        }
        return "Arte Classica"
    }
    
    private var artistName: String {
        if card.name.contains("_experience") {
            if !isCollectionCompleteFor(card.name) {
                return "Locked"
            }
            return "Keepsy Collection"
        }
        return artwork?.artist ?? "Artista Sconosciuto"
    }
    
    private var creationYear: String {
        if card.name.contains("_experience") {
            if !isCollectionCompleteFor(card.name) {
                return "????"
            }
            return "2026"
        }
        guard let raw = artwork?.createdAt else { return "Data Sconosciuta" }
        // Se contiene uno spazio o T è un timestamp ISO — estrai solo i primi 4 chars (anno)
        // Altrimenti è già una stringa leggibile tipo "1535 ca."
        if raw.contains("-") && raw.count > 10 {
            return String(raw.prefix(4))
        }
        return raw
    }
    
    private var descriptionText: String {
        if card.name.contains("_experience") {
            if !isCollectionCompleteFor(card.name) {
                return "To be unlocked when you have the whole collection"
            }
            return "Congratulations! You have completed the entire museum collection and unlocked this exclusive Keepsy Experience Card. You've proven yourself a true art connoisseur!"
        }
        return artwork?.description ?? "Nessuna descrizione disponibile per questa opera d'arte"
    }
    
    var body: some View {
        GeometryReader { geometry in
        let screenHeight = geometry.size.height
        
        // Calcolo delle dimensioni e offset in base alla sorgente (Album vs Bustina)
        let cardWidth: CGFloat = 310
        let cardHeight: CGFloat = 470
        
        ZStack {
            if isZoomingFromAlbum {
                // Sfondo scuro — solo in modalità non-album (in album mode il genitore gestisce overlayOpacity)
                if !isZoomingFromAlbum {
                    Color.black
                        .opacity(animateContent ? 0.6 : 0.0)
                        .ignoresSafeArea()
                        .onTapGesture { closeAction() }
                } else {
                    // Tap su sfondo in album mode
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeAction() }
                }

                if showFullDetail {
                    // ── DETTAGLIO COMPLETO (SilverMetalCard + flip) ──────────
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
                    // ── CARTA GRANDE IN ALTO ─────────────────────────────────
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

                    if card.name.contains("_experience") && !isCollectionCompleteFor(card.name) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "5168C4"), Color(hex: "3F53B3")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("?")
                                .font(.system(size: 110, weight: .black))
                                .foregroundColor(.white)
                        }
                        .frame(width: cardW, height: cardH)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: Color(hex: "5168C4").opacity(0.4), radius: 30, x: 0, y: 15)
                        .position(x: geometry.size.width / 2,
                                  y: cardTopY + cardH / 2)
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
                        .position(x: geometry.size.width / 2,
                                  y: cardTopY + cardH / 2)
                        // In album mode animateContent is true from the start — no entrance animation needed here,
                        // the parent's inspectionOpacity crossfade already handles the reveal.
                        .opacity(1.0)
                        .onTapGesture {
                            HapticManager.shared.triggerImpact(style: .medium)
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                showFullDetail = true
                            }
                        }
                    }

                    // ── MINI-SHEET IN BASSO ──────────────────────────────────
                    let collapsedY = screenHeight - sheetPeekHeight
                    let expandedY  = screenHeight * 0.42
                    let sheetY     = miniSheetExpanded ? expandedY : collapsedY
                    let sheetHeight: CGFloat = screenHeight * 0.62

                    VStack(spacing: 0) {
                        // Handle
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 36, height: 5)
                            .padding(.top, 12)
                            .padding(.bottom, 18)

                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                // Categoria
                                Text(categoryName.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))

                                // Titolo
                                Text(card.name.contains("_experience") && !isCollectionCompleteFor(card.name) ? "Locked Experience" : card.title)
                                    .font(.system(size: 26, weight: .black))
                                    .foregroundColor(.white)
                                    .lineLimit(3)

                                // Artista + data
                                Text("\(artistName); \(creationYear)")
                                    .font(.system(size: 15).italic())
                                    .foregroundColor(.white.opacity(0.65))

                                Color.white.opacity(0.1).frame(height: 1).padding(.vertical, 4)
                                Text(descriptionText)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(hex: "D1D1D6"))
                                    .lineSpacing(4)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                        .scrollDisabled(!miniSheetExpanded)
                    }
                    .frame(width: geometry.size.width, height: sheetHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(LinearGradient(
                                colors: [Color(hex: "2C2C2E"), Color(hex: "121214")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color(hex: "B1B1B1"), Color(hex: "464646")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ), lineWidth: 1.5
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: -4)
                    .position(x: geometry.size.width / 2,
                              y: sheetY + miniSheetDrag + sheetHeight / 2)
                    .offset(y: animateContent ? 0 : screenHeight)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                miniSheetDrag = min(max(v.translation.height, -200), 200)
                            }
                            .onEnded { v in
                                let drag = v.translation.height
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                    miniSheetDrag = 0
                                    if drag < -60 {
                                        miniSheetExpanded = true
                                    } else if drag > 60 {
                                        if miniSheetExpanded {
                                            miniSheetExpanded = false
                                        } else {
                                            closeAction()
                                        }
                                    }
                                }
                            }
                    )
                }

                // Back button
                if animateContent && !showFullDetail {
                    Button(action: { closeAction() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                            Text("Back")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(.white)
                        .frame(width: 85, height: 44)
                        .background(Capsule().fill(Color(hex: "383838")))
                    }
                    .position(x: 30 + 85/2, y: 83 + 44/2)
                }
            } else {
                // Sfondo scuro per focalizzare la carta. Un tap qui chiude l'ispezione.
                Color.black
                    .opacity(animateContent ? 0.85 : 0.0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { closeAction() }
                
                // CARTA CON METALLO/OLOGRAMMA — nascosta in modalità album (la flying card fa già da carta)
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
                        // Same frame as front — fill+clipped, PNG retro has its own border
                        Image("retro")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                        
                        // FRONTE DELLA CARTA
                        let index = CardDatabase.allArtworkNames.firstIndex(of: card.name)
                        let goldBorder = LinearGradient(
                            colors: [
                                Color(hex: "F5E480"), Color(hex: "F1B40A"),
                                Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        
                        let isAlreadyOwned = CardDatabase.getDuplicatesInActivePack().contains(card.name) || CardDatabase.getRevealedCards().contains(card.name)
                        ArtworkCardFrontView(
                            name: card.name,
                            title: card.title,
                            cardIndex: index,
                            width: 310,
                            height: 470,
                            isRevealed: isRevealed,
                            goldBorder: goldBorder,
                            showCheckmark: isAlreadyOwned
                        )
                        .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
                    }
                }
                .matchedGeometryEffectOptional(id: "card_\(card.name)", in: isZoomingFromAlbum ? nil : namespace, isSource: false)
                .offset(y: isZoomingFromAlbum ? -50 : (namespace == nil ? (animateContent ? 0 : 380) : 0))
                .scaleEffect(namespace == nil && !isZoomingFromAlbum ? (animateContent ? 1.0 : 0.75) : 1.0)
                .opacity(animateContent ? 1.0 : 0.0)
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

                // Back button (bustina mode)
                if animateContent {
                    Button(action: { closeAction() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                            Text("Back")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(.white)
                        .frame(width: 85, height: 44)
                        .background(Capsule().fill(Color(hex: "383838")))
                    }
                    .position(x: 30 + 85/2, y: 83 + 44/2)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            if isZoomingFromAlbum {
                // In album mode the parent controls opacity via inspectionOpacity crossfade.
                // We must NOT run our own entrance animation or we get a double-card effect.
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
        } // GeometryReader
        .ignoresSafeArea()
    }
    
    private func closeAction() {
        HapticManager.shared.triggerImpact(style: .light)
        if isZoomingFromAlbum {
            // In album mode the parent (CollectionAlbumView.startCloseAnimation) owns the
            // entire close sequence — crossfade of inspectionOpacity, then flying-card
            // shrink back to the cell.  We must call onClose() immediately so the parent
            // can start its 0.15s fade-out right away; any internal animation here
            // would fight with that crossfade and produce a double-card flash.
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

// MARK: - CardFullDetailView — dettaglio completo con SilverMetalCard e flip

struct CardFullDetailView: View {
    let card: ArtworkCard
    var namespace: Namespace.ID? = nil
    let onClose: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedRotation: Double = 0.0
    @State private var animateContent: Bool = false

    private let cardWidth: CGFloat = 310
    private var cardHeight: CGFloat { 470 }

    private var isRevealed: Bool { CardDatabase.getRevealedCards().contains(card.name) || card.name.contains("_experience") }

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
                    // Same frame as front — fill+clipped, PNG retro has its own border
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
                    let isAlreadyOwned = CardDatabase.getDuplicatesInActivePack().contains(card.name) || CardDatabase.getRevealedCards().contains(card.name)
                    ArtworkCardFrontView(
                        name: card.name,
                        title: card.title,
                        cardIndex: index,
                        width: 310,
                        height: 470,
                        isRevealed: isRevealed,
                        goldBorder: goldBorder,
                        showCheckmark: isAlreadyOwned
                    )
                        .opacity(isFrontShowing ? 1 : 0)
                }
            }
            .scaleEffect(animateContent ? 1.0 : 0.85)
            .opacity(animateContent ? 1.0 : 0.0)
            .onTapGesture {
                SoundManager.shared.playSound(named: "giro_carta")
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { accumulatedRotation += 180 }
            }
            .gesture(DragGesture()
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

            if animateContent {
                Button(action: { closeDetail() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .foregroundColor(.white)
                    .frame(width: 85, height: 44)
                    .background(Capsule().fill(Color(hex: "383838")))
                }
                .position(x: 30 + 85/2, y: 83 + 44/2)
            }
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
