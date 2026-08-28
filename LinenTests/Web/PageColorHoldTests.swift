// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing
import WebKit

@testable import Linen

/// A commit hands the tab a document that has not painted yet, and a snapshot
/// of it comes back the base white WebKit paints before the page does. The
/// chrome takes its colour from that snapshot, so a reload of a dark website
/// used to flash white between two dark frames. The colour is held from the
/// commit until the load finishes.
@MainActor
struct PageColorHoldTests {
    private static let sentinel = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private static let page = "<html><body style=\"margin:0;background:#101820\"></body></html>"

    private func window() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private func isSentinel(_ color: NSColor?) -> Bool {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return false }
        return rgb.redComponent > 0.9 && rgb.greenComponent < 0.1
    }

    private func showing(_ tab: BrowserTab, in window: NSWindow) async -> Bool {
        tab.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView?.addSubview(tab.webView)
        window.orderBack(nil)
        tab.realizeDeferredSession()
        guard await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)) else { return false }
        tab.webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.test/"))
        guard await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)) else { return false }
        return await waitUntil { tab.isShowingRealPage && !tab.holdsPageColor }
    }

    @Test(.boundedWebViews) func aFinishedLoadLeavesNoHold() async {
        let model = BrowserModel(database: .temporary())
        let tab = model.ensureActiveTab()
        let window = window()
        defer { window.orderOut(nil) }

        #expect(await showing(tab, in: window))

        #expect(!tab.holdsPageColor)
    }

    @Test(.boundedWebViews) func aHeldTabKeepsTheColourItIsShowing() async {
        let model = BrowserModel(database: .temporary())
        let tab = model.ensureActiveTab()
        let window = window()
        defer { window.orderOut(nil) }

        #expect(await showing(tab, in: window))

        tab.pageColor = Self.sentinel
        tab.holdPageColorUntilLoaded()
        #expect(tab.holdsPageColor, "a tab on a website holds rather than clears")
        tab.measureBandUnderBar()

        let replaced = await waitUntil(timeout: .seconds(3)) { !isSentinel(tab.pageColor) }
        #expect(!replaced, "the held tab measured the document behind the hold")
    }

    @Test(.boundedWebViews) func releasingTheHoldMeasuresTheDocument() async {
        let model = BrowserModel(database: .temporary())
        let tab = model.ensureActiveTab()
        let window = window()
        defer { window.orderOut(nil) }

        #expect(await showing(tab, in: window))

        tab.pageColor = Self.sentinel
        tab.releasePageColorHold()
        tab.measureBandUnderBar()

        #expect(await waitUntil(timeout: .seconds(3)) { !isSentinel(tab.pageColor) })
    }

    @Test func leavingAWebsiteClearsTheColourInsteadOfHoldingIt() {
        let model = BrowserModel(database: .temporary())
        let tab = model.ensureActiveTab()

        tab.pageColor = Self.sentinel
        tab.holdPageColorUntilLoaded()

        #expect(tab.pageColor == nil)
        #expect(!tab.holdsPageColor)
    }
}
