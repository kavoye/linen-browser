// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing
import WebKit

@testable import Linen

/// Background tab audio rests entirely on this: a `WKWebView` that leaves the
/// window stops playing, and every host in the app can be torn down while its
/// page is making sound - switching tabs, opening Settings over the content
/// area, closing the media dock. The shelf is what makes those survivable, so
/// the invariant it provides is pinned here rather than left to a listener
/// noticing the music stop.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct WebViewParkingTests {
    /// The arrangement `BrowserHost` builds: a plain root holding the hosting
    /// view's stand-in and the shelf as siblings.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        root.addSubview(WebViewParkingShelf(frame: .zero))
        window.contentView = root
        return window
    }

    private func host(_ webView: WKWebView, in window: NSWindow) -> WebViewContainer {
        let container = WebViewContainer(webView: webView)
        container.parksWhenIdle = true
        container.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView?.addSubview(container)
        return container
    }

    @Test func aHostLeavingTheWindowParksItsWebViewRatherThanOrphaningIt() {
        let window = makeWindow()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let container = host(webView, in: window)
        #expect(webView.window === window)

        // What SwiftUI does when Settings replaces the content area: the host
        // is detached, which is the last moment there is a window to park in.
        container.removeFromSuperview()

        #expect(webView.window === window)
        #expect(webView.superview is WebViewParkingShelf)
    }

    @Test func theNextHostTakesTheViewBackOffTheShelf() {
        let window = makeWindow()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        host(webView, in: window).removeFromSuperview()

        let second = host(webView, in: window)

        #expect(webView.superview === second)
        // One web view, one host: two would fight over it and the card goes
        // black. See `MediaModel.pictureWebView`.
        #expect(window.contentView?.subviews.compactMap { $0 as? WebViewContainer }.count == 1)
        #expect(
            window.contentView?.subviews
                .first { $0 is WebViewParkingShelf }?
                .subviews.isEmpty == true
        )
    }

    /// The other setting is for hosts that own their view outright, and it has
    /// to keep meaning what it says: leave, and take the page with you.
    @Test func aHostThatDoesNotParkLetsTheViewLeaveTheWindow() {
        let window = makeWindow()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let container = WebViewContainer(webView: webView)
        container.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView?.addSubview(container)

        container.removeFromSuperview()

        #expect(webView.window == nil)
    }
}
