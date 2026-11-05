import SwiftUI

/// Fits the complete printed card to the shared size, adapting both dimensions independently.
struct SpecialCardImageView: View {
    private static let boundsCache = NSCache<UIImage, NSValue>()
    private let image: UIImage?
    private let cardBounds: CGRect

    init(image: UIImage?) {
        self.image = image
        guard let image else {
            self.cardBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        if let cached = Self.boundsCache.object(forKey: image) {
            self.cardBounds = cached.cgRectValue
        } else {
            let bounds = image.cgImage?.visibleCardBounds() ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            Self.boundsCache.setObject(NSValue(cgRect: bounds), forKey: image)
            self.cardBounds = bounds
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(x: 1 / cardBounds.width, y: 1 / cardBounds.height)
                    .offset(
                        x: (0.5 - cardBounds.midX) * geometry.size.width / cardBounds.width,
                        y: (0.5 - cardBounds.midY) * geometry.size.height / cardBounds.height
                    )
            }
        }
        .clipped()
    }
}

private extension CGImage {
    func visibleCardBounds() -> CGRect? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                // Export shadows extend far beyond the card at less than 10% opacity.
                for x in 0..<width where bytes[y * bytesPerRow + x * 4 + 3] >= 26 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(
                x: CGFloat(minX) / CGFloat(width),
                y: CGFloat(minY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height)
            )
        }
        return bounds
    }
}
