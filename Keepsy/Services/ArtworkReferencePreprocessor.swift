import Accelerate
import CoreGraphics

/// Keeps the original reference alongside a quieter view of the composition.
/// Fine, repetitive marks can dominate feature extraction in detailed paintings.
actor ArtworkReferencePreprocessor {
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

    private func grayscaleContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }
}
