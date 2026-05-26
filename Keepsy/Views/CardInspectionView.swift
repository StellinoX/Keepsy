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
                            Image(card.imageName)
                                .resizable()
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
            }
            
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
