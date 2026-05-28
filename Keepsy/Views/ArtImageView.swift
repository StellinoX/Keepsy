import SwiftUI

struct ArtImageView: View {
    let cardName: String
    
    @State private var localImage: UIImage?
    
    init(cardName: String) {
        self.cardName = cardName
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
                .task {
                    await waitForImage()
                }
            }
        }
    }
    
    private func waitForImage() async {
        // Poll every 0.5s until the image is found on disk
        while !Task.isCancelled {
            // Run heavy I/O on background thread to prevent UI freezing
            if let img = await Task.detached(operation: { CardDatabase.localImage(for: cardName) }).value {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.localImage = img
                    }
                }
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
