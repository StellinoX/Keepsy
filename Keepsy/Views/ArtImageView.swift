import SwiftUI

struct ArtImageView: View {
    let cardName: String
    var isRevealed: Bool
    
    @State private var localImage: UIImage?
    
    init(cardName: String, isRevealed: Bool = true) {
        self.cardName = cardName
        self.isRevealed = isRevealed
        self._localImage = State(initialValue: CardDatabase.localImage(for: cardName))
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
                    Color.black.opacity(0.2) // Dark background to make ProgressView visible
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
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
            if let img = CardDatabase.localImage(for: cardName) {
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
