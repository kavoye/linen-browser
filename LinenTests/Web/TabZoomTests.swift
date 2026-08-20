// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

/// The zoom the menus act on: stepped in and out through the tab, clamped to
/// one range, and put back by Actual Size - which is disabled exactly when
/// `isZoomed` says there is nothing for it to do.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct TabZoomTests {
    /// Actual Size must greet a new tab disabled - including when the user's
    /// default zoom isn't 100%, which is exactly the case "compare against
    /// 1" would get wrong.
    @Test func aFreshTabIsNotZoomed() {
        let tab = BrowserTab()
        #expect(!tab.isZoomed)
    }

    @Test func zoomingEnablesActualSizeAndResetPutsEverythingBack() {
        let tab = BrowserTab()
        let before = tab.webView.pageZoom

        tab.zoomIn()
        #expect(abs(tab.webView.pageZoom - (before + TabWebView.zoomStep)) < 0.001)
        #expect(tab.isZoomed)

        tab.resetZoom()
        #expect(!tab.isZoomed)
        #expect(abs(tab.webView.pageZoom - BrowserSettings.shared.pageZoom) < 0.005)
        #expect(tab.webView.magnification == 1)
    }

    /// A leftover pinch counts as zoomed too - Actual Size answers for the
    /// pair, so its enabled state has to as well.
    @Test func aPinchAloneCountsAsZoomed() {
        let tab = BrowserTab()
        tab.webView.magnification = 1.6
        #expect(tab.isZoomed)

        tab.resetZoom()
        #expect(!tab.isZoomed)
    }

    /// The sizes live on the web view, which SwiftUI can't watch. Every path
    /// that changes one has to say so, or a menu goes on showing the answer
    /// it was built with - which is how Actual Size came to ignore a zoom.
    @Test func everyZoomPathAnnouncesItself() {
        let tab = BrowserTab()
        var seen = tab.zoomChanges

        tab.zoomIn()
        #expect(tab.zoomChanges > seen)
        seen = tab.zoomChanges

        tab.zoomOut()
        #expect(tab.zoomChanges > seen)
        seen = tab.zoomChanges

        tab.resetZoom()
        #expect(tab.zoomChanges > seen)
        seen = tab.zoomChanges

        // ⌘-scroll and the pinch happen inside the web view and come back
        // through this hook.
        (tab.webView as? TabWebView)?.onZoomChanged?()
        #expect(tab.zoomChanges > seen)
    }

    /// ⌘ with the wheel zooms; ⌘ with two fingers on a trackpad is a scroll,
    /// the way it is everywhere else on the Mac - the pinch is that gesture's
    /// zoom. Gesture phases are the only thing separating the two.
    @Test func commandScrollZoomsOnAWheelAndNotOnATrackpad() {
        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            configuration: WKWebViewConfiguration()
        )
        let start = view.pageZoom

        view.scrollWheel(with: Self.commandScroll(lines: 3, touchSurfacePhase: 2))
        #expect(view.pageZoom == start)

        view.scrollWheel(with: Self.commandScroll(lines: 3, touchSurfacePhase: nil))
        #expect(view.pageZoom > start)
    }

    /// A ⌘-held scroll, either off a wheel (no phase) or off a touch surface
    /// (`kCGScrollPhaseChanged` and friends).
    private static func commandScroll(lines: Int32, touchSurfacePhase: Int64?) -> NSEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .line,
            wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0
        )!
        event.flags = .maskCommand
        if let touchSurfacePhase {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: touchSurfacePhase)
        }
        return NSEvent(cgEvent: event)!
    }

    @Test func zoomStopsAtTheEndsOfTheRange() {
        let tab = BrowserTab()

        for _ in 0..<40 {
            tab.zoomIn()
        }
        #expect(abs(tab.webView.pageZoom - TabWebView.zoomRange.upperBound) < 0.001)

        for _ in 0..<40 {
            tab.zoomOut()
        }
        #expect(abs(tab.webView.pageZoom - TabWebView.zoomRange.lowerBound) < 0.001)
    }
}
