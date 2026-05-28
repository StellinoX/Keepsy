import SwiftUI

struct ArtImageView: View {
    let cardName: String
    var isRevealed: Bool
    
    @State private var localImage: UIImage?
    
    init(cardName: String, isRevealed: Bool = true) {
        self.cardName = cardName
        self.isRevealed = isRevealed
        if let cached = CardDatabase.imageCache.object(forKey: cardName as NSString) {
            self._localImage = State(initialValue: cached)
        } else {
            self._localImage = State(initialValue: CardDatabase.localImage(for: cardName))
        }
    }
    
    var body: some View {
        Group {
            if let img = localImage {
                Image(uiImage: img)
                    .resizable()
            } else {
                ZStack {
                    CardDatabase.gradientFor(name: cardName)
                        .opacity(0.8)
                }
                .onAppear {
                    if let img = CardDatabase.localImage(for: cardName) {
                        self.localImage = img
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ArtworkImageDownloaded"))) { notification in
                    if let name = notification.userInfo?["internalName"] as? String, name == cardName {
                        if let img = CardDatabase.localImage(for: cardName) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.localImage = img
                            }
                        }
                    }
                }
            }
        }
    }
}

