// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The line between links the web view renders and links that launch other
/// apps. Drawn wrong in one direction, extension pages get offered to the
/// system; wrong in the other, `mailto:` goes back to doing nothing.
struct ExternalSchemeTests {
    @Test(arguments: [
        "http://example.com",
        "HTTPS://EXAMPLE.COM/path",
        "about:blank",
        "blob:https://example.com/2b0a",
        "data:text/html,hello",
        "file:///tmp/page.html",
        "javascript:void(0)",
        "webkit-extension://install-id/options.html",
    ])
    func webSchemesStayInTheWebView(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(ExternalApp.staysInWebView(url))
    }

    @Test(arguments: [
        "mailto:hello@example.com",
        "tel:+15551234567",
        "facetime:hello@example.com",
        "zoommtg://zoom.us/join?confno=1",
        "vscode://file/tmp/x.swift",
    ])
    func appSchemesAreOfferedToTheSystem(_ address: String) throws {
        let url = try #require(URL(string: address))
        #expect(!ExternalApp.staysInWebView(url))
    }
}

/// A dialog's message is the page's to write, so its length is the page's
/// to abuse.
struct PageDialogMessageTests {
    @Test func ordinaryMessagesPassThroughUntouched() {
        #expect(PageDialogs.capped("Are you sure?") == "Are you sure?")
    }

    @Test func aRunawayMessageIsCappedWithAnEllipsis() {
        let flood = String(repeating: "a", count: 100_000)
        let shown = PageDialogs.capped(flood)
        #expect(shown.count == 1501)
        #expect(shown.hasSuffix("…"))
    }
}
