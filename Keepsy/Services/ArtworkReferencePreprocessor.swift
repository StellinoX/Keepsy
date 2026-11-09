import Accelerate
import CoreGraphics

/// Keeps the original reference alongside a quieter view of the composition.
/// Fine, repetitive marks can dominate feature extraction in detailed paintings.
actor ArtworkReferencePreprocessor {
    nonisolated struct Reference: Sendable {
        let image: CGImage
        let widthFraction: CGFloat
    }

    static let shared = ArtworkReferencePreprocessor()
    func compositionImage(from image: CGImage) -> CGImage? {
        let scale = min(1, 512 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let input = grayscaleContext(width: width, height: height),
              let output = grayscaleContext(width: width, height: height),
              let inputData = input.data, let outputData = output.data else { return nil }

        // CPU processing also works without a Metal rendering context. The full
        // canvas is preserved, so both references have the same physical width.
        input.interpolationQuality = .high
        input.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var source = vImage_Buffer(data: inputData, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: input.bytesPerRow)
        var destination = vImage_Buffer(data: outputData, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: output.bytesPerRow)
        let kernel: [Int16] = [1, 2, 1, 2, 4, 2, 1, 2, 1]
        let error = vImageConvolve_Planar8(&source, &destination, nil, 0, 0,
            kernel, 3, 3, 16, 0, vImage_Flags(kvImageEdgeExtend))
        guard error == kvImageNoError else { return nil }

        let pixels = outputData.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * output.bytesPerRow + x
                let contrast = (Double(pixels[offset]) - 127.5) * 1.1 + 127.5
                pixels[offset] = UInt8(clamping: Int(contrast.rounded()))
            }
        }
        return output.makeImage()
    }

    func detailImages(from image: CGImage) -> [Reference] {
        // Use two overlapping regions along the longer axis. Each keeps three
        // outer edges and enough of the composition to disambiguate repeated marks.
        let isLandscape = image.width > image.height
        let length = max(image.width, image.height)
        let cropLength = Int((Double(length) * 0.6).rounded())
        guard cropLength > 0, cropLength < length else { return [] }
        let width = isLandscape ? cropLength : image.width
        let height = isLandscape ? image.height : cropLength
        let widthFraction = CGFloat(width) / CGFloat(image.width)

        return [0, length - cropLength].compactMap { offset in
            let rect = CGRect(x: isLandscape ? offset : 0, y: isLandscape ? 0 : offset,
                width: width, height: height)
            guard let crop = image.cropping(to: rect),
                  let detail = highContrastImage(from: crop) else { return nil }
            return Reference(image: detail, widthFraction: widthFraction)
        }
    }

    private func highContrastImage(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = grayscaleContext(width: width, height: height),
              let data = context.data else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: context.bytesPerRow)
        var destination = source
        guard vImageEqualization_Planar8(&source, &destination, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        return context.makeImage()
    }

    private func grayscaleContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }
}
