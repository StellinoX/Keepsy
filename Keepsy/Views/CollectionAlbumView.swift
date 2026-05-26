import SwiftUI

struct CollectionAlbumView: View {
    var museumLocation: String? = nil // nil = all
    var showCloseButton: Bool = false
    var onClose: (() -> Void)? = nil
    
    // 5 colonne come richiesto
    let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]
    
    @State private var foundCards: Set<String> = []
    @State private var revealedCards: Set<String> = []
    @State private var hasSyncedWithCloud = false
    @State private var inspectedCard: ArtworkCard? = nil
    
    var headerTitle: String {
        return "CAPODIMONTE"
    }
    
    var filteredArtworks: [String] {
        return CardDatabase.allArtworkNames
    }
    
    var body: some View {
        ZStack {
            // Sfondo scuro con griglia
            Color(red: 0.05, green: 0.05, blue: 0.1).edgesIgnoringSafeArea(.all)
            GridBackground()
            
            VStack(spacing: 20) {
                // Se è presente il tasto chiudi, mostriamo una Top Bar
                if showCloseButton {
                    HStack {
                        Button(action: {
                            onClose?()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .bold()
                                Text("Indietro")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                        }
                        Spacer()
                        
                        Text(headerTitle)
                            .font(.system(.headline, design: .monospaced))
                            .bold()
                            .foregroundColor(.white)
                            .padding(.trailing, 40) // per bilanciare il tasto indietro
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                
                // Collection Box
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12)) // Grigio scuro simile al mockup
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filteredArtworks, id: \.self) { name in
                                AlbumCardCell(
                                    name: name,
                                    isRevealed: revealedCards.contains(name)
                                )
                                .onTapGesture {
                                    if revealedCards.contains(name) {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            inspectedCard = ArtworkCard(
                                                name: name,
                                                imageName: name,
                                                gradient: CardDatabase.gradientFor(name: name),
                                                isFlipped: true // Per assicurarci che parta girata frontalmente o con il behavior giusto
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16)) // Non fa uscire la ScrollView dai bordi arrotondati
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            foundCards = CardDatabase.getFoundCards()
            revealedCards = CardDatabase.getRevealedCards()
        }
        .task {
            // Fetch latest artwork links from cloud API
            await CardDatabase.syncWithCloud()
            hasSyncedWithCloud = true // Triggers a UI refresh!
        }
        .overlay(
            Group {
                if let inspectedCard = inspectedCard {
                    CardInspectionView(card: inspectedCard) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            self.inspectedCard = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .zIndex(100)
                }
            }
        )
    }
}

struct AlbumCardCell: View {
    let name: String
    let isRevealed: Bool
    private var remoteURL: URL? {
        if let urlString = CardDatabase.remoteArtworks[name]?.imageUrl {
            return URL(string: urlString)
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            if isRevealed {
                // Card sbloccata (rivelata in AR): immagine chiara
                VStack(spacing: 0) {
                    Group {
                        if let url = remoteURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .blur(radius: isRevealed ? 0 : 15) // Blur se non rivelata
                                } else if phase.error != nil {
                                    Image("CardBackLogo").resizable()
                                } else {
                                    ProgressView()
                                }
                            }
                        } else {
                            // Nessun URL dal cloud
                            Image("CardBackLogo")
                                .resizable()
                        }
                    }
                    .aspectRatio(contentMode: .fill)
                    .padding(.top, 3)
                    .padding(.horizontal, 3)
                    .cornerRadius(4)
                    
                    Spacer()
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 15)
                }
                .background(CardDatabase.gradientFor(name: name))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CardDatabase.borderGradientFor(name: name), lineWidth: 1))
            } else {
                // Card bloccata (sagoma nera)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.15), lineWidth: 1))
            }
        }
        .aspectRatio(111/168, contentMode: .fit) // Mantiene le proporzioni originali Figma
    }
}
