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
                if isRevealed {
                    Image(uiImage: img)
                        .resizable()
                } else {
                    if let pixelatedImg = img.resizeToPixelated(size: CGSize(width: 16, height: 20)) {
                        Image(uiImage: pixelatedImg)
                            .resizable()
                            .interpolation(.none)
                    } else {
                        Image(uiImage: img)
                            .resizable()
                    }
                }
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

fileprivate extension UIImage {
    func resizeToPixelated(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
