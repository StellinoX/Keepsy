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
    
    private var isRevealed: Bool {
        CardDatabase.getRevealedCards().contains(card.name)
    }
    
    var body: some View {
        ZStack {
            if !isZoomingFromAlbum {
                // Sfondo scuro per focalizzare la carta. Un tap qui chiude l'ispezione.
                Color.black
                    .opacity(animateContent ? 0.85 : 0.0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { closeAction() }
            }
            
            // Contenitore della carta fronte/retro con effetto olografico metallico
            SilverMetalCardView(
                width: 310,
                height: 470,
                isEnabled: isFrontShowing,
                tiltX: Double(dragOffset.width) / 155.0, // Normalizza il trascinamento per la lucentezza
                tiltY: Double(dragOffset.height) / 235.0,
                customRotationX: Double(-dragOffset.height) / 10.0,
                customRotationY: currentRotation
            ) {
                ZStack {
                    // RETRO DELLA CARTA
                    // RETRO DELLA CARTA (MUSEUM ARCHIVES DETAILS SHEET)
                    ZStack {
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
                    .frame(width: 310, height: 470)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)) // Il retro è specchiato di default
                    
                    // FRONTE DELLA CARTA
                    VStack(spacing: 0) {
                        Group {
                            ArtImageView(cardName: card.name, isRevealed: isRevealed)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 350)
                        .cornerRadius(20)
                        .padding(.top, 15)
                        .padding(.horizontal, 15)
                        
                        Spacer()
                        
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 105)
                                
                            if isRevealed {
                                VStack(spacing: 4) {
                                    Text(card.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                    
                                    if let description = card.description {
                                        Text(description)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.horizontal, 10)
                            } else {
                                VStack(spacing: 4) {
                                    Text(card.title)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .frame(width: 310, height: 470)
                    .background(card.gradient)
                    .cornerRadius(24)
                    // Nascondiamo il fronte se la rotazione totale supera i 90 gradi
                    .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
                }
            }
            .matchedGeometryEffectOptional(id: "card_\(card.name)", in: namespace, isSource: false)
            .offset(y: namespace == nil && !isZoomingFromAlbum ? (animateContent ? 0 : 380) : 0)
            .scaleEffect(isZoomingFromAlbum ? externalScale : (namespace == nil ? (animateContent ? 1.0 : 0.75) : 1.0))
            .opacity(isZoomingFromAlbum ? externalOpacity : (animateContent ? 1.0 : 0.0))
            .onTapGesture { closeAction() }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            // Aggiungiamo o togliamo 180 in base alla direzione
                            if value.translation.width > 80 {
                                accumulatedRotation += 180
                            } else if value.translation.width < -80 {
                                accumulatedRotation -= 180
                            }
                            dragOffset = .zero
                        }
                    }
            )
            
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
                // Se viene dall'album, mostriamo il tasto back dopo che la card si è ingrandita
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
    
    // Controlla se la faccia frontale della carta è rivolta verso l'utente
    private var isFrontShowing: Bool {
        let absRot = abs(currentRotation.truncatingRemainder(dividingBy: 360))
        return !(absRot > 90 && absRot < 270)
    }
    
    // Calcola la rotazione totale continua
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
