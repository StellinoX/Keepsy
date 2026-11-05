import CoreGraphics
import simd

nonisolated enum ArtworkScanVisibility {
    /// AR image anchors lie in their local X/Z plane. Tracking alone is not
    /// enough: all four corners must still be inside the displayed camera view.
    static func containsArtwork(clipTransform: simd_float4x4, size: CGSize) -> Bool {
        let halfWidth = Float(size.width / 2)
        let halfHeight = Float(size.height / 2)
        guard halfWidth > 0, halfHeight > 0 else { return false }
        return [-halfWidth, halfWidth].allSatisfy { x in
            [-halfHeight, halfHeight].allSatisfy { z in
                let point = clipTransform * SIMD4<Float>(x, 0, z, 1)
                return point.w > 0 && point.w.isFinite &&
                    abs(point.x) <= point.w && abs(point.y) <= point.w
            }
        }
    }
}
