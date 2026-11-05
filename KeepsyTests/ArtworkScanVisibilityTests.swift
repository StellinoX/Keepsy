import CoreGraphics
import simd
import Testing
@testable import Keepsy

struct ArtworkScanVisibilityTests {
    // A front-facing image maps local X/Z coordinates onto the screen X/Y axes.
    private var frontFacing: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1)
        ))
    }

    @Test func fullyFramedArtworkIsVisible() {
        #expect(ArtworkScanVisibility.containsArtwork(clipTransform: frontFacing,
            size: CGSize(width: 1, height: 1)))
    }

    @Test func trackedArtworkOutsideTheScreenIsNotVisible() {
        var offscreen = frontFacing
        offscreen.columns.3.x = 2
        #expect(!ArtworkScanVisibility.containsArtwork(clipTransform: offscreen,
            size: CGSize(width: 1, height: 1)))
    }

    @Test func partiallyCroppedArtworkInterruptsTheHold() {
        var cropped = frontFacing
        cropped.columns.3.x = 0.75
        #expect(!ArtworkScanVisibility.containsArtwork(clipTransform: cropped,
            size: CGSize(width: 1, height: 1)))
    }

    @Test func artworkBehindTheCameraIsNotVisible() {
        var behind = frontFacing
        behind.columns.3.w = -1
        #expect(!ArtworkScanVisibility.containsArtwork(clipTransform: behind,
            size: CGSize(width: 1, height: 1)))
    }
}
