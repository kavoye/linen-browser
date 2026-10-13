// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing

@testable import Linen

/// The 1px light line at the window's top edge, visible over a dark toolbar
/// band. AppKit's titlebar decoration draws it over the content, so it is
/// checked here the way the user saw it: rendered pixels at the very top of
/// a window whose content is dark.
@MainActor
struct WindowSeamTests {
    /// A window in the browser's chrome configuration, holding a dark band
    /// where the page-coloured toolbar would be.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "seam-test")
        window.toolbarStyle = .unified
        // Light appearance draws the strongest rim, so the test looks where
        // the seam is worst.
        window.appearance = NSAppearance(named: .aqua)

        let band = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        band.wantsLayer = true
        band.layer?.backgroundColor = CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        window.contentView = band
        return window
    }

    /// Per point, not per pixel: the rim is about a point tall, so a 1x display
    /// lands it on rows a 2x display spreads across two.
    private func topEdgeReds(of window: NSWindow, points: Int) -> [CGFloat] {
        guard let frameView = window.contentView?.superview else { return [] }
        frameView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return [] }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let scale = max(1, rep.pixelsWide / max(1, Int(frameView.bounds.width)))
        let midX = rep.pixelsWide / 2
        return (0..<points).compactMap { point in
            (0..<scale)
                .compactMap { rep.colorAt(x: midX, y: point * scale + $0)?.redComponent }
                .max()
        }
    }

    /// The decoration is matched by private class name, so a rename by Apple
    /// would leave the window untouched and the seam back.
    @Test func theDecorationIsFoundAndHidden() {
        let window = makeWindow()
        defer { window.close() }
        #expect(BrowserHost.hideTitlebarDecoration(of: window))
    }

    /// The fix: with the decoration hidden, the top edge is the band's own
    /// colour all the way to the first row of pixels.
    @Test func theTopEdgeStaysTheBandsColour() throws {
        let window = makeWindow()
        defer { window.close() }
        BrowserHost.hideTitlebarDecoration(of: window)
        let reds = topEdgeReds(of: window, points: 4)
        try #require(reds.count == 4)
        for (row, red) in reds.enumerated() {
            #expect(red < 0.2, "point \(row) shows a light seam over the dark band: \(reds)")
        }
    }
}
