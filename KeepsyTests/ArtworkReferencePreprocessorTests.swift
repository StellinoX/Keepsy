import CoreGraphics
import Foundation
import Testing
@testable import Keepsy

struct ArtworkReferencePreprocessorTests {
    @Test func compositionPreservesFullPaintingAndAspectRatio() async throws {
        let source = try makeImage(width: 1024, height: 768)
        let result = try #require(await ArtworkReferencePreprocessor.shared.compositionImage(from: source))
        #expect(result.width == 512)
        #expect(result.height == 384)
    }

    @Test func smallReferenceIsNotUpscaled() async throws {
        let source = try makeImage(width: 200, height: 300)
        let result = try #require(await ArtworkReferencePreprocessor.shared.compositionImage(from: source))
        #expect(result.width == source.width)
        #expect(result.height == source.height)
    }

    @Test func micropatternIsSuppressedWhileLargeShapesRemainDistinct() async throws {
        // Two broad bands overlaid with one-pixel dots: preserve the composition
        // while removing the repetitive detail that competes with its features.
        let source = try makeImage(width: 512, height: 512, dotted: true)
        let result = try #require(await ArtworkReferencePreprocessor.shared.compositionImage(from: source))
        let pixels = try grayscalePixels(result)
        let first = pixels[128 * 512 + 128]
        let neighbor = pixels[128 * 512 + 129]
        let second = pixels[128 * 512 + 384]
        #expect(abs(Int(first) - Int(neighbor)) < 12)
        #expect(Int(second) - Int(first) > 60)
    }

    @Test func portraitDetailsKeepFullWidthAndEmphasizeOppositeEnds() async throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 200,
            bitsPerComponent: 8, bytesPerRow: 100,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<200 {
            for x in 0..<100 {
                data[y * context.bytesPerRow + x] = (x < 50) == (y < 100) ? 100 : 120
            }
        }

        let source = try #require(context.makeImage())
        let details = await ArtworkReferencePreprocessor.shared.detailImages(from: source)
        try #require(details.count == 2)
        let top = details[0]
        let bottom = details[1]
        #expect(top.image.width == 100 && top.image.height == 120)
        #expect(bottom.image.width == 100 && bottom.image.height == 120)
        #expect(top.widthFraction == 1 && bottom.widthFraction == 1)

        let topPixels = try grayscalePixels(top.image)
        let bottomPixels = try grayscalePixels(bottom.image)
        let lastRow = (bottom.image.height - 1) * bottom.image.width
        #expect(Int(topPixels[75]) - Int(topPixels[25]) > 20)
        #expect(Int(bottomPixels[lastRow + 25]) - Int(bottomPixels[lastRow + 75]) > 20)
    }

    @Test func landscapeDetailsScalePhysicalWidthToTheCrop() async throws {
        let source = try makeImage(width: 204, height: 100)
        let details = await ArtworkReferencePreprocessor.shared.detailImages(from: source)
        try #require(details.count == 2)
        for detail in details {
            #expect(detail.image.width == 122 && detail.image.height == 100)
            #expect(detail.widthFraction == CGFloat(122) / 204)
        }
    }

    private func makeImage(width: Int, height: Int, dotted: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        if dotted, let buffer = context.data?.assumingMemoryBound(to: UInt8.self) {
            for y in 0..<height {
                for x in 0..<width {
                    let base = x < width / 2 ? 65 : 175
                    buffer[y * width + x] = UInt8(base + ((x + y).isMultiple(of: 2) ? 0 : 60))
                }
            }
        }
        return try #require(context.makeImage())
    }

    private func grayscalePixels(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return Array(UnsafeBufferPointer(start: data, count: image.width * image.height))
    }
}
