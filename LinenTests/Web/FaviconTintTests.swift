// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import Testing

@testable import Linen

/// The colour a tab wears comes from its icon. A washed-out average would
/// make every site grey, so the reading is weighted towards the pixels a
/// person would call the icon's colour, and it has to survive an icon that
/// is mostly transparent.
@MainActor
struct FaviconTintTests {
    private func icon(_ draw: (NSSize) -> Void, size: CGFloat = 32) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(image.size)
        image.unlockFocus()
        return image
    }

    private func filled(_ color: NSColor, size: CGFloat = 32) -> NSImage {
        icon({ bounds in
            color.setFill()
            NSRect(origin: .zero, size: bounds).fill()
        }, size: size)
    }

    private func components(_ color: Color?) -> (red: Double, green: Double, blue: Double)? {
        guard let color, let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
    }

    @Test func aSolidIconReadsAsItsOwnColour() {
        let parts = components(FaviconTint.of(filled(.systemRed)))

        #expect(parts != nil)
        #expect((parts?.red ?? 0) > 0.6)
        #expect((parts?.green ?? 1) < 0.4)
        #expect((parts?.blue ?? 1) < 0.4)
    }

    @Test func nothingIsNoColour() {
        #expect(FaviconTint.of(nil) == nil)
    }

    @Test func aTransparentIconHasNothingToRead() {
        let blank = NSImage(size: NSSize(width: 16, height: 16))

        #expect(FaviconTint.of(blank) == nil)
    }

    /// A mostly transparent icon with one saturated mark reads as the mark:
    /// the clear pixels are skipped rather than averaged into grey.
    @Test func aMarkOnClearGroundReadsAsTheMark() {
        let image = icon { bounds in
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: bounds.width / 4, height: bounds.height / 4).fill()
        }
        let parts = components(FaviconTint.of(image))

        #expect(parts != nil)
        #expect((parts?.blue ?? 0) > (parts?.red ?? 1))
    }

    @Test func aTabKeepsTheColourItHadWhenTheIconGoesMissing() {
        let tab = UUID()
        defer { FaviconTint.forget(tab) }

        let first = FaviconTint.of(filled(.systemGreen), heldBy: tab)
        #expect(first != nil)

        #expect(FaviconTint.of(nil, heldBy: tab) == first, "a missing icon keeps the colour it had")
    }

    @Test func forgettingATabDropsWhatItWasHolding() {
        let tab = UUID()
        _ = FaviconTint.of(filled(.systemOrange), heldBy: tab)

        FaviconTint.forget(tab)

        #expect(FaviconTint.of(nil, heldBy: tab) == nil)
    }
}
