import SwiftUI

struct CardInspectionView: View {
    let card: ArtworkCard
    let onClose: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedRotation: Double = 0.0 // Rotazione continua
    
    var body: some View {
        ZStack {
            // Sfondo scuro per focalizzare la carta. Un tap qui chiude l'ispezione.
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onClose() }
            
            // Contenitore della carta fronte/retro
            ZStack {
                // RETRO DELLA CARTA
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Circle()
                        .fill(Color(white: 0.01))
                        .frame(width: 90)
                        .shadow(color: .white.opacity(0.08), radius: 4, x: 2, y: 2)
                        .shadow(color: .black, radius: 4, x: -2, y: -2)
                }
                .frame(width: 310, height: 470)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0)) // Il retro è specchiato di default
                
                // FRONTE DELLA CARTA
                VStack(spacing: 0) {
                    Group {
                        let isRevealed = CardDatabase.getRevealedCards().contains(card.name)
                        if !isRevealed, let uiImage = UIImage(named: card.imageName)?.resize(to: CGSize(width: 70, height: 85)) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .interpolation(.none)
                        } else {
                            Image(card.imageName)
                                .resizable()
                        }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 280, height: 350)
                    .cornerRadius(20)
                    .padding(.top, 15)
                    .padding(.horizontal, 15)
                    
                    Spacer()
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 105)
                }
                .frame(width: 310, height: 470)
                .background(card.gradient)
                .cornerRadius(24)
                // Nascondiamo il fronte se la rotazione totale supera i 90 gradi
                .opacity(abs(currentRotation.truncatingRemainder(dividingBy: 360)) > 90 && abs(currentRotation.truncatingRemainder(dividingBy: 360)) < 270 ? 0 : 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
            
            // Applichiamo la rotazione combinata: il flip (180 o 0) + il drag interattivo
            .rotation3DEffect(.degrees(currentRotation), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(Double(-dragOffset.height) / 10.0), axis: (x: 1, y: 0, z: 0))
            
            // Gestures: Tap per chiudere, Drag per girare/inclinare
            .onTapGesture { onClose() }
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
        }
    }
    
    // Calcola la rotazione totale continua
    private var currentRotation: Double {
        let dragRotation = Double(dragOffset.width) / 4.0
        return accumulatedRotation + dragRotation
    }
}
