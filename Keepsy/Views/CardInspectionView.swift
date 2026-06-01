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
        let cardWidth: CGFloat = isZoomingFromAlbum ? 250 : 310
        let cardHeight: CGFloat = isZoomingFromAlbum ? 380 : 470
        let _ = isZoomingFromAlbum ? 70 : 90
        
        // Offset Y della modale in base allo stato
        let modalHeight: CGFloat = 480
        let collapsedOffset = modalHeight - 190
        let expandedOffset = modalHeight - 440
        let currentModalOffset = (sheetState == .collapsed ? collapsedOffset : expandedOffset) + sheetDragOffset
        
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
                    // RETRO DELLA CARTA (MUSEUM ARCHIVES DETAILS SHEET / ALBUM POCKET PREVIEW)
                    ZStack {
                        if isZoomingFromAlbum {
                            // Layout identico alle bustine, proporzionato per la collezione (250x380)
                            VStack(spacing: 0) {
                                ArtImageView(cardName: card.name, isRevealed: isRevealed)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 226, height: 260)
                                    .cornerRadius(16)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 12)
                                
                                Spacer()
                                
                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 108)
                                        
                                    if isRevealed {
                                        VStack(spacing: 4) {
                                            Text(card.title)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                            
                                            if let description = card.description {
                                                Text(description)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.8))
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(3)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                    } else {
                                        VStack(spacing: 4) {
                                            Text(card.title)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                }
                            }
                            .frame(width: 250, height: 380)
                            .background(Color(hex: "1A0E6E"))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(
                                LinearGradient(colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                            .shadow(color: Color.white.opacity(0.12), radius: 15)
                        } else {
                            // Modalità bustina: il meraviglioso Museum Archive Details Sheet
                            RoundedRectangle(cornerRadius: 24)
                                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            if isRevealed, let details = CardDatabase.remoteArtworks[card.name] {
                                VStack(alignment: .leading, spacing: 10) {
                                    // Title & Inventory
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(details.title)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(details.artist ?? "Artista Ignoto")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.orange)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if let inv = details.inventoryNumber, !inv.isEmpty {
                                            Text(inv)
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(4)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.2))
                                    
                                    // Technical Details Grid
                                    VStack(alignment: .leading, spacing: 5) {
                                        if let date = details.date, !date.isEmpty {
                                            HStack(alignment: .top) {
                                                Text("Data:")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 75, alignment: .leading)
                                                Text(date)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        if let tech = details.technique, !tech.isEmpty {
                                            HStack(alignment: .top) {
                                                Text("Tecnica:")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 75, alignment: .leading)
                                                Text(tech)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        if let dim = details.dimensions, !dim.isEmpty {
                                            HStack(alignment: .top) {
                                                Text("Dimensioni:")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 75, alignment: .leading)
                                                Text(dim)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.2))
                                    
                                    // Scrollable Description
                                    ScrollView {
                                        Text(details.description ?? "Nessuna descrizione disponibile per quest'opera.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.leading)
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(16)
                                // Reverse the horizontal mirroring so text reads properly when flipped
                                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                            } else {
                                Circle()
                                    .fill(Color(white: 0.01))
                                    .frame(width: 90)
                                    .shadow(color: .white.opacity(0.08), radius: 4, x: 2, y: 2)
                                    .shadow(color: .black, radius: 4, x: -2, y: -2)
                            }
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay(RoundedRectangle(cornerRadius: isZoomingFromAlbum ? 20 : 24).stroke(Color.white.opacity(0.1), lineWidth: isZoomingFromAlbum ? 0.8 : 1))
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    
                    // FRONTE DELLA CARTA
                    if isZoomingFromAlbum {
                        // Modalità Album: solo opera d'arte pulita ed elegante, testi nella modale
                        VStack(spacing: 0) {
                            ArtImageView(cardName: card.name, isRevealed: isRevealed)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 226, height: 356)
                                .cornerRadius(16)
                                .padding(.top, 12)
                                .padding(.horizontal, 12)
                        }
                        .frame(width: 250, height: 380)
                        .background(Color.white)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(
                            LinearGradient(colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                        .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
                    } else {
                        // Modalità Bustina: artwork pulita con info strip, design nuovo
                        VStack(spacing: 0) {
                            ArtImageView(cardName: card.name, isRevealed: isRevealed)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 280, height: 350)
                                .clipped()
                                .cornerRadius(20)
                                .padding(.top, 15)
                                .padding(.horizontal, 15)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                    .lineLimit(2)
                                if let details = CardDatabase.remoteArtworks[card.name],
                                   let artist = details.artist, !artist.isEmpty {
                                    Text(artist)
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(white: 0.45))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            Spacer()
                        }
                        .frame(width: 310, height: 470)
                        .background(Color.white)
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(
                            LinearGradient(colors: [Color(hex: "F5E480"), Color(hex: "F1B40A"), Color(hex: "9A6F00"), Color(hex: "F1B40A"), Color(hex: "F5E480")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                        .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
                    }
                }
            }
            .matchedGeometryEffectOptional(id: "card_\(card.name)", in: isZoomingFromAlbum ? nil : namespace, isSource: false)
            .offset(y: namespace == nil && !isZoomingFromAlbum ? (animateContent ? 0 : 380) : 0)
            .scaleEffect(namespace == nil && !isZoomingFromAlbum ? (animateContent ? 1.0 : 0.75) : 1.0)
            .opacity(isZoomingFromAlbum ? 0 : (animateContent ? 1.0 : 0.0))
            .onTapGesture {
                if isZoomingFromAlbum {
                    // Tap per girare la carta se aperta dall'album
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                        accumulatedRotation += 180
                    }
                } else {
                    // Chiude l'ispezione al tap sulla carta se aperta dal pacchetto
                    closeAction()
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
            
            // MODALE DRAGGABILE (BOTTOM SHEET) - Solo per la modalità Album
            if isZoomingFromAlbum {
                VStack(spacing: 0) {
                    // Maniglia di trascinamento superiore
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        if isRevealed {
                            // Badge Categoria — Capsule grigia come nello screenshot
                            Text(categoryName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(white: 0.22)))
                                .padding(.bottom, 18)
                            
                            // Titolo Opera
                            Text(card.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 4)
                                .lineLimit(2)
                            
                            // Autore e Anno
                            Text("\(artistName); \(creationYear)")
                                .font(.system(size: 14, weight: .medium))
                                .italic()
                                .foregroundColor(.white.opacity(0.65))
                                .padding(.bottom, 18)
                            
                            // Descrizione Completa (Scrollable)
                            ScrollView(showsIndicators: false) {
                                Text(descriptionText)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineSpacing(5)
                                    .multilineTextAlignment(.leading)
                                    .padding(.bottom, 40)
                            }
                        } else {
                            // Se l'opera non è ancora rivelata in AR
                            Text("Collezione")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(white: 0.18)))
                                .padding(.bottom, 18)
                            
                            Text(card.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 10)
                            
                            Text("Scansiona l'opera reale con la fotocamera AR per sbloccare i dettagli completi, la storia e le informazioni su questa carta da collezione.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.5))
                                .lineSpacing(5)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .frame(width: geometry.size.width - 24, height: modalHeight)
                .background(
                    RoundedRectangle(cornerRadius: 33)
                        .fill(Color(hex: "1C1C1E").opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 33)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "B1B1B1"), Color(hex: "B1B1B1").opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.6), radius: 39, x: 0, y: 4)
                )
                .offset(y: screenHeight/2 - modalHeight/2 + currentModalOffset + (animateContent ? 0 : modalHeight))
                .opacity(animateContent ? 1.0 : 0.0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let drag = value.translation.height
                            if sheetState == .expanded && drag < 0 {
                                sheetDragOffset = drag * 0.2
                            } else {
                                sheetDragOffset = drag
                            }
                        }
                        .onEnded { value in
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            let totalDrag = value.translation.height
                            
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                if totalDrag < -60 || velocity < -120 {
                                    sheetState = .expanded
                                } else if totalDrag > 60 || velocity > 120 {
                                    sheetState = .collapsed
                                }
                                sheetDragOffset = 0
                            }
                        }
                )
            }
            
            // PULSANTE BACK IN ALTO
            if !isZoomingFromAlbum || animateContent {
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
