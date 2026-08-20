// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Testing
import WebKit

@testable import Linen

/// The rule the browser window consults before AppKit's beep-on-unclaimed-key
/// fallback: a key that travelled through a web view was the page's to
/// decline, everything else keeps the system behavior.
@MainActor
@Suite(.boundedWebViews)
struct WebKeyEchoTests {
    @Test func aKeyEchoedByTheWebViewIsSilenced() {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(WebKeyEcho.shouldSilenceUnhandledKey(from: webView))
    }

    /// WebKit sometimes hands focus to an inner view of its own; anything
    /// inside the web view still means "the page was asked".
    @Test func aResponderInsideTheWebViewIsSilencedToo() {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let inner = NSView(frame: .zero)
        webView.addSubview(inner)
        #expect(WebKeyEcho.shouldSilenceUnhandledKey(from: inner))
    }

    /// A text view, the sidebar, or any plain view keeps AppKit's own answer -
    /// silencing there would mute beeps that mean something.
    @Test func respondersOutsideAWebViewKeepTheBeep() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let plain = NSView(frame: .zero)
        let text = NSTextView(frame: .zero)
        window.contentView?.addSubview(plain)
        window.contentView?.addSubview(text)

        #expect(!WebKeyEcho.shouldSilenceUnhandledKey(from: plain))
        #expect(!WebKeyEcho.shouldSilenceUnhandledKey(from: text))
        #expect(!WebKeyEcho.shouldSilenceUnhandledKey(from: window))
        #expect(!WebKeyEcho.shouldSilenceUnhandledKey(from: nil))
    }

    /// A view sitting *beside* a web view in the window - the sidebar next to
    /// the page - is not inside it, and must not borrow its silence.
    @Test func aSiblingOfTheWebViewIsNotSilenced() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 150, height: 200))
        let sidebar = NSView(frame: NSRect(x: 150, y: 0, width: 150, height: 200))
        container.addSubview(webView)
        container.addSubview(sidebar)

        #expect(WebKeyEcho.shouldSilenceUnhandledKey(from: webView))
        #expect(!WebKeyEcho.shouldSilenceUnhandledKey(from: sidebar))
    }
}
