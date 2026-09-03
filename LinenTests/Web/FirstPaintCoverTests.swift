// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

@MainActor
struct FirstPaintCoverTests {
    @Test func theCommitDefaultFlashesOnADarkMac() {
        #expect(BrowserTab.wouldFlash(painting: .white, inDark: true))
    }

    @Test func aDarkPageDoesNotFlashOnADarkMac() {
        let github = NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        #expect(!BrowserTab.wouldFlash(painting: github, inDark: true))
    }

    @Test func aDarkPageFlashesOnALightMac() {
        #expect(BrowserTab.wouldFlash(painting: .black, inDark: false))
        #expect(!BrowserTab.wouldFlash(painting: .white, inDark: false))
    }

    @Test func brightnessIsWeightedNotAveraged() {
        #expect(BrowserTab.wouldFlash(painting: .systemGreen, inDark: true))
        #expect(!BrowserTab.wouldFlash(painting: .systemBlue, inDark: true))
    }

    @Test func anUnknownColourIsNeverHeldFor() {
        #expect(!BrowserTab.wouldFlash(painting: nil, inDark: true))
    }
}
