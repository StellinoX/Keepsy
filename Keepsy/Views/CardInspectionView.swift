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
    
    // Smooth internal animation trigger
    @State private var animateContent: Bool = false
    
    // Bottom Sheet State (utilizzato solo se proveniamo dall'album)
    enum SheetState {
        case collapsed, expanded
    }
    @State private var sheetState: SheetState = .collapsed
    @State private var sheetDragOffset: CGFloat = 0
    
    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(card.name)
    }
    
    private var artwork: NetworkArtwork? {
        CardDatabase.remoteArtworks[card.name]
    }
    
    // Categorizzazione dinamica e intelligente dell'opera basata sull'artista
    private var categoryName: String {
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
        artwork?.artist ?? "Artista Sconosciuto"
    }
    
    private var creationYear: String {
        artwork?.createdAt ?? "Data Sconosciuta"
    }
    
    private var descriptionText: String {
        artwork?.description ?? "Nessuna descrizione disponibile per questa opera d'arte"
    }
    
    var body: some View {
        GeometryReader { geometry in
        let screenHeight = geometry.size.height
        
        // Calcolo delle dimensioni e offset in base alla sorgente (Album vs Bustina)
        let cardWidth: CGFloat = 310
        let cardHeight: CGFloat = 470
        
        ZStack {
            if !isZoomingFromAlbum {
                // Sfondo scuro per focalizzare la carta. Un tap qui chiude l'ispezione.
                Color.black
                    .opacity(animateContent ? 0.85 : 0.0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { closeAction() }
            }
            
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
                    // RETRO DELLA CARTA (MUSEUM ARCHIVES DETAILS SHEET)
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(LinearGradient(
                                colors: [Color(hex: "2D1C76"), Color(hex: "432B3F")],
                                startPoint: .top,
                                endPoint: .bottom
                            ))

                        Image("LogoKeepsy")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 150)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(hex: "B1B1B1"), lineWidth: 2)
                    }
                    .frame(width: cardWidth, height: cardHeight)
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
            .offset(y: isZoomingFromAlbum ? -50 : (namespace == nil ? (animateContent ? 0 : 380) : 0))
            .scaleEffect(namespace == nil && !isZoomingFromAlbum ? (animateContent ? 1.0 : 0.75) : 1.0)
            .opacity(animateContent ? 1.0 : 0.0)
            .onTapGesture {
                // Tap per girare la carta
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    accumulatedRotation += 180
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            if value.translation.width > 80 {
                                accumulatedRotation += 180
                            } else if value.translation.width < -80 {
                                accumulatedRotation -= 180
                            }
                            dragOffset = .zero
                        }
                    }
            )
            
            // PULSANTE BACK IN ALTO
            if animateContent {
                VStack {
                    HStack {
                        Button(action: {
                            closeAction()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Back")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 85, height: 44)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(hex: "E36D13"), Color(hex: "FEBB0B")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            )
                            .shadow(color: Color(hex: "E36D13").opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.top, 61)
                        .padding(.leading, 30)
                        .opacity(animateContent ? 1.0 : 0.0)
                        
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            if isZoomingFromAlbum {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        animateContent = true
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
            withAnimation(.easeOut(duration: 0.15)) {
                animateContent = false
            }
        }
        onClose()
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
