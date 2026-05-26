import SwiftUI

struct CardInspectionView: View {
    let card: ArtworkCard
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
            // Sfondo scuro per focalizzare la carta. Un tap qui chiude l'ispezione.
            Color.black
                .opacity(animateContent ? 0.85 : 0.0)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { closeAction() }
            
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
                            ArtImageView(cardName: card.name)
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
                                    Text(card.name.replacingOccurrences(of: "_", with: " "))
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
                                Text("UNKNOWN ARTWORK")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
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
            .scaleEffect(animateContent ? 1.0 : 0.6)
            .opacity(animateContent ? 1.0 : 0.0)
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
            
            // Elegant Back Button (top-left aligned with same Figma specifications)
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
            .position(x: 30 + 85/2, y: 83 + 44/2)
            .opacity(animateContent ? 1.0 : 0.0)
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                animateContent = true
            }
        }
    }
    
    private func closeAction() {
        HapticManager.shared.triggerImpact(style: .light)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            animateContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onClose()
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
