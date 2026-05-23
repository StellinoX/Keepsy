import SwiftUI

struct CardView: View {
    @Binding var card: ArtworkCard
    var onInspect: (() -> Void)? = nil
    
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // RETRO (MISURE FIGMA: 111x168)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Circle()
                    .fill(Color(white: 0.01))
                    .frame(width: 45)
                    .shadow(color: .white.opacity(0.08), radius: 2, x: 1, y: 1)
                    .shadow(color: .black, radius: 2, x: -1, y: -1)
            }
            .frame(width: 111, height: 168)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .opacity(card.isFlipped ? 0 : 1)
            
            // FRONTE (MISURE FIGMA: 111x168 con Immagine 101x125)
            VStack(spacing: 0) {
                // Immagine pixelata con padding di 5px
                Group {
                    // Aumentata la risoluzione (da 12x15 a 25x30) per rendere i pixel più piccoli
                    if let uiImage = UIImage(named: card.imageName)?.resize(to: CGSize(width: 25, height: 30)) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.none) // Effetto pixel netto
                    } else {
                        Image(card.imageName)
                            .resizable()
                    }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 101, height: 125)
                .cornerRadius(12) // Aumentato per matchare la carta
                .padding(.top, 5)
                .padding(.horizontal, 5) // Padding su entrambi i lati
                
                Spacer()
                
                // Parte inferiore colorata (restanti 38px di altezza)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 38)
            }
            .frame(width: 111, height: 168)
            .background(card.gradient)
            .cornerRadius(12)
            .shadow(radius: 5)
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
    }
}
