import SwiftUI

/// Fits the printed face at its original aspect ratio after trimming transparent padding.
struct SpecialCardImageView: View {
    private static let faceCache = NSCache<UIImage, UIImage>()
    private let image: UIImage?

    init(image: UIImage?) {
        guard let image else {
            self.image = nil
            return
        }
        if let cached = Self.faceCache.object(forKey: image) {
            self.image = cached
            return
        }
        let face: UIImage
        if let cgImage = image.cgImage,
           let bounds = cgImage.visibleCardBounds(),
           let cropped = cgImage.cropping(to: bounds) {
            face = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        } else {
            face = image
        }
        Self.faceCache.setObject(face, forKey: image)
        self.image = face
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
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
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        }
        return bounds
    }
}
