// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

/// The toolbar's ink is decided from the averaged pixels of the band under
/// the bar, and the averaging crops that band out of a snapshot by *row*.
/// These tests hold the one assumption that cannot be checked by reading the
/// code: which end of the image the crop takes. If a change to the averaging
/// flips it, the ink inverts on every site whose top and body differ - which
/// is exactly the bug the measurement exists to prevent.
@MainActor
struct BandMeasurementTests {
    /// Red band at the top, blue below, in an explicitly top-down image: the
    /// average of the top fifth must come back red.
    @Test func averagesTheTopBandNotTheBottom() throws {
        let image = NSImage(
            size: NSSize(width: 100, height: 100),
            flipped: true
        ) { _ in
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 100).fill()
            NSColor.red.setFill()
            // Flipped drawing space: y = 0 is the top.
            NSRect(x: 0, y: 0, width: 100, height: 20).fill()
            return true
        }
        let average = try #require(BrowserTab.averageOfTopBand(of: image, fraction: 0.2))
        let rgb = try #require(average.usingColorSpace(.sRGB))
        #expect(rgb.redComponent > 0.8, "the crop took the wrong end of the image")
        #expect(rgb.blueComponent < 0.2)
    }

    /// A band taller than the whole image - a very short web view - must
    /// clamp rather than fail, and still answer from the pixels.
    @Test func clampsAnOversizedBand() throws {
        let image = NSImage(
            size: NSSize(width: 40, height: 10),
            flipped: true
        ) { _ in
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 40, height: 10).fill()
            return true
        }
        let average = try #require(BrowserTab.averageOfTopBand(of: image, fraction: 4.4))
        let rgb = try #require(average.usingColorSpace(.sRGB))
        #expect(rgb.redComponent < 0.1)
    }

    /// A busy band averages to its mean rather than failing: half black, half
    /// white comes back mid-grey.
    @Test func aBusyBandAveragesToItsMean() throws {
        let image = NSImage(
            size: NSSize(width: 100, height: 100),
            flipped: true
        ) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 100).fill()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 50, height: 20).fill()
            return true
        }
        let average = try #require(BrowserTab.averageOfTopBand(of: image, fraction: 0.2))
        let rgb = try #require(average.usingColorSpace(.sRGB))
        #expect(abs(rgb.redComponent - 0.5) < 0.15)
    }
}
