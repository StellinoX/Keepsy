import Testing
import SwiftUI
import UIKit
@testable import Keepsy

/// Tests for the `Color(hex:)` initializer used by the design tokens.
@Suite
@MainActor
struct ColorHexTests {

    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

    @Test func sixDigitHexParsesRGB() {
        let c = rgba(Color(hex: "FF0000"))
        #expect(close(c.r, 1) && close(c.g, 0) && close(c.b, 0) && close(c.a, 1))
    }

    @Test func threeDigitHexExpandsNibbles() {
        // "F00" → FF0000
        let c = rgba(Color(hex: "F00"))
        #expect(close(c.r, 1) && close(c.g, 0) && close(c.b, 0))
    }

    @Test func eightDigitHexParsesARGB() {
        // Alpha 0x80 ≈ 0.502
        let c = rgba(Color(hex: "80FFFFFF"))
        #expect(close(c.a, 0x80 / 255.0))
        #expect(close(c.r, 1) && close(c.g, 1) && close(c.b, 1))
    }

    @Test func leadingHashIsIgnored() {
        let a = rgba(Color(hex: "#F1B40A"))
        let b = rgba(Color(hex: "F1B40A"))
        #expect(close(a.r, b.r) && close(a.g, b.g) && close(a.b, b.b))
    }

    @Test func goldDesignTokenMatchesSpec() {
        // Gold border token F1B40A → R=0xF1, G=0xB4, B=0x0A.
        let c = rgba(Color(hex: "F1B40A"))
        #expect(close(c.r, 0xF1 / 255.0))
        #expect(close(c.g, 0xB4 / 255.0))
        #expect(close(c.b, 0x0A / 255.0))
    }
}
