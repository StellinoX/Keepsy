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
            self._localImage = State(initialValue: nil)
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
                    loadAsynchronously()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ArtworkImageDownloaded"))) { notification in
                    if let name = notification.userInfo?["internalName"] as? String, name == cardName {
                        loadAsynchronously()
                    }
                }
            }
        }
    }
    
    private func loadAsynchronously() {
        if let cached = CardDatabase.imageCache.object(forKey: cardName as NSString) {
            self.localImage = cached
            return
        }
        
        Task.detached(priority: .userInitiated) {
            if let img = CardDatabase.localImage(for: cardName) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.localImage = img
                    }
                }
            }
        }
    }
}

