// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

/// A wash has to stay visible on whatever colour the chrome takes. It is
/// measured from that colour rather than from a fixed alpha, so widening the
/// tint later cannot quietly erase a hover.
@MainActor
struct ChromeWashTests {
    private func wash(_ color: NSColor, isLight: Bool) -> ChromeWash {
        ChromeWash.of(color, isLight: isLight)
    }

    @Test func aWashIsMeasuredFromTheChromeItSitsOn() {
        let dark = wash(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1), isLight: false)
        let light = wash(NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), isLight: true)

        #expect(dark.luminance < 0.1)
        #expect(light.luminance > 0.9)
    }

    /// The ink follows the page, the way the glyphs already do: a dark website
    /// under a light Mac still gets a light wash.
    @Test func theInkFollowsTheChromeNotTheMac() {
        #expect(ChromeWash(isLight: false).ink == Color.white)
        #expect(ChromeWash(isLight: true).ink == Color.black)
    }

    private func alpha(of color: Color) -> Double {
        var alpha: CGFloat = 0
        NSColor(color).usingColorSpace(.sRGB)?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return Double(alpha)
    }

    /// A dark chrome keeps the alpha it always had: a tenth of white already
    /// moves a near-black ground further than the eye needs.
    @Test func aDarkChromeKeepsTheAlphaItAlwaysHad() {
        for brightness in [0.0, 0.05, 0.105, 0.2] {
            let chrome = NSColor(srgbRed: brightness, green: brightness, blue: brightness, alpha: 1)
            let hover = alpha(of: wash(chrome, isLight: false).layer(0.10))
            #expect(abs(hover - 0.10) < 0.001, "brightness \(brightness)")
        }
    }

    /// A pale chrome is where a fixed alpha fails: a tenth of black over near
    /// white is a step of under four, so the wash has to buy more.
    @Test func aPaleChromeAsksForMore() {
        let pale = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        let hover = alpha(of: wash(pale, isLight: true).layer(0.10))

        #expect(hover > 0.10, "a tenth barely moves a pale ground")
        #expect(hover < 0.15, "and a pale ground carries a wash a long way")
    }

    /// Mid grey is the other weak ground, and it lands between the two.
    @Test func aMidChromeLandsBetweenThem() {
        let mid = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let hover = alpha(of: wash(mid, isLight: PageInk.isLight(mid, scheme: .dark)).layer(0.10))

        // Mid grey is the most expensive ground there is: moving it a step
        // the eye can see costs more ink than either end.
        #expect(hover > 0.15)
        #expect(hover < 0.3)
    }

    /// Every layer keeps its order however the chrome moves.
    @Test func theLayersKeepTheirOrder() {
        for chrome in [
            NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1),
            NSColor(srgbRed: 0.5, green: 0.45, blue: 0.6, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
        ] {
            let wash = wash(chrome, isLight: PageInk.isLight(chrome, scheme: .dark))
            let faint = alpha(of: wash.layer(0.04))
            let hover = alpha(of: wash.layer(0.10))
            let selection = alpha(of: wash.layer(0.12))
            #expect(faint < hover)
            #expect(hover < selection)
        }
    }

    /// Publishing the lightness without the wash leaves a light chrome
    /// painting the dark chrome's white, which is no hover at all. Every
    /// place that says one has to say the other.
    @Test func everyPlaceThatPublishesTheLightnessAlsoPublishesTheWash() throws {
        let sources = [
            "Linen/UI/Sidebar/Sidebar.swift",
            "Linen/UI/Content/ContentNavBar.swift",
            "Linen/UI/Shell/BrowserView.swift",
            "Linen/Media/Lyrics/LyricsView.swift",
        ]
        for path in sources {
            let url = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: path)
            let text = try String(contentsOf: url, encoding: .utf8)
            let lightness = text.components(separatedBy: "environment(\\.chromeIsLight").count - 1
            let wash = text.components(separatedBy: "environment(\\.chromeWash").count - 1
            #expect(lightness == wash, "\(path) publishes \(lightness) and \(wash)")
        }
    }

    @Test func aWashWithNothingMeasuredFallsBackToTheScheme() {
        #expect(ChromeWash.of(nil, isLight: false).luminance < 0.5)
        #expect(ChromeWash.of(nil, isLight: true).luminance > 0.5)
    }
}
