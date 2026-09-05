// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing
import WebKit

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

    @Test(.boundedWebViews) func aPageWithNoProcessToPaintItIsUncoveredAtOnce() {
        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            configuration: WebViewPool.makeConfiguration()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        let inDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        view.underPageBackgroundColor = inDark ? .white : .black
        #expect(BrowserTab.wouldFlash(painting: view.underPageBackgroundColor, inDark: inDark))
        #expect((view.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value == 0)

        let tab = BrowserTab(adopting: view)
        tab.coverUntilPresented()

        #expect(tab.hasPresentedContent)
    }

    @Test(.boundedWebViews) func aFrameThatWouldFlashStaysCoveredUntilTheHoldLifts() async throws {
        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            configuration: WebViewPool.makeConfiguration()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        let inDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tab = BrowserTab(adopting: view)
        view.loadHTMLString("<html><body style='background:\(inDark ? "#fff" : "#000")'></body></html>", baseURL: nil)
        try await Task.sleep(for: .seconds(1))
        view.underPageBackgroundColor = inDark ? .white : .black

        tab.coverUntilPresented()

        #expect(!tab.hasPresentedContent)
        try await Task.sleep(for: .milliseconds(120))
        #expect(!tab.hasPresentedContent)
        try await Task.sleep(for: .seconds(1.5))
        #expect(tab.hasPresentedContent)
    }
}
