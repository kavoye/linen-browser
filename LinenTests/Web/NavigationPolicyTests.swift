// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews, .exclusiveExternalApp)
struct NavigationPolicyTests {
    private final class StubAction: WKNavigationAction {
        var stubbedRequest = URLRequest(url: URL(string: "https://example.com/")!)
        var stubbedType: WKNavigationType = .other
        var stubbedModifiers: NSEvent.ModifierFlags = []
        var stubbedDownload = false

        override var request: URLRequest {
            stubbedRequest
        }

        override var navigationType: WKNavigationType {
            stubbedType
        }

        override var modifierFlags: NSEvent.ModifierFlags {
            stubbedModifiers
        }

        override var shouldPerformDownload: Bool {
            stubbedDownload
        }

        override var targetFrame: WKFrameInfo? {
            nil
        }
    }

    private func subject(extensionBase: URL? = nil) -> (BrowserTab, TabNavigationDelegate) {
        let tab: BrowserTab
        if let extensionBase {
            tab = BrowserTab(extensionHost: ExtensionPageHost(
                configuration: WKWebViewConfiguration(),
                baseURL: extensionBase,
                name: "Stub Extension",
                icon: nil
            ))
        } else {
            tab = BrowserTab()
        }
        return (tab, TabNavigationDelegate(tab: tab))
    }

    private func decide(
        _ delegate: TabNavigationDelegate,
        _ tab: BrowserTab,
        _ action: StubAction
    ) -> WKNavigationActionPolicy? {
        var decided: WKNavigationActionPolicy?
        delegate.webView(tab.webView, decidePolicyFor: action) { decided = $0 }
        return decided
    }

    private func action(
        _ address: String,
        type: WKNavigationType = .other,
        modifiers: NSEvent.ModifierFlags = []
    ) -> StubAction {
        let stub = StubAction()
        stub.stubbedRequest = URLRequest(url: URL(string: address)!)
        stub.stubbedType = type
        stub.stubbedModifiers = modifiers
        return stub
    }

    // MARK: - Ordinary navigation

    @Test func anOrdinaryWebPageIsAllowed() {
        let (tab, delegate) = subject()
        #expect(decide(delegate, tab, action("https://example.com/page")) == .allow)
    }

    @Test func aPlainHTTPPageIsStillTheWebAndIsAllowed() {
        let (tab, delegate) = subject()
        #expect(decide(delegate, tab, action("http://example.com/page")) == .allow)
    }

    @Test func aRequestThatAsksToBeDownloadedIsNotNavigatedTo() {
        let (tab, delegate) = subject()
        let stub = action("https://example.com/archive.zip")
        stub.stubbedDownload = true

        #expect(decide(delegate, tab, stub) == .download)
    }

    // MARK: - Links that leave the browser

    @Test func aLinkForAnotherAppNeverNavigates() {
        let (tab, delegate) = subject()
        for address in ["mailto:someone@example.com", "tel:+15550100", "zoommtg://zoom.us/join?confno=1"] {
            #expect(decide(delegate, tab, action(address)) == .cancel, "\(address)")
        }
    }

    @Test func theSchemesThePageIsAllowedToDriveItselfWith() {
        let (tab, delegate) = subject()
        for address in ["about:blank", "data:text/html,hi", "blob:https://example.com/x"] {
            #expect(decide(delegate, tab, action(address)) == .allow, "\(address)")
        }
    }

    // MARK: - Modifier clicks

    @Test func commandClickingALinkOpensATabInsteadOfNavigating() {
        let (tab, delegate) = subject()
        var opened: (URL, Bool)?
        tab.onOpenInNewTab = { opened = ($0, $1) }

        let policy = decide(delegate, tab, action(
            "https://example.com/target", type: .linkActivated, modifiers: [.command]
        ))

        #expect(policy == .cancel)
        #expect(opened?.0.absoluteString == "https://example.com/target")
        #expect(opened?.1 == false)
    }

    @Test func commandShiftClickingAsksForTheTabToBeActivated() {
        let (tab, delegate) = subject()
        var opened: (URL, Bool)?
        tab.onOpenInNewTab = { opened = ($0, $1) }

        let policy = decide(delegate, tab, action(
            "https://example.com/target", type: .linkActivated, modifiers: [.command, .shift]
        ))

        #expect(policy == .cancel)
        #expect(opened?.1 == true)
    }

    @Test func shiftClickingALinkOpensItBesideThePage() {
        let (tab, delegate) = subject()
        var split: URL?
        tab.onOpenInSplit = { split = $0 }
        tab.onOpenInNewTab = { _, _ in Issue.record("shift alone must not open a tab") }

        let policy = decide(delegate, tab, action(
            "https://example.com/target", type: .linkActivated, modifiers: [.shift]
        ))

        #expect(policy == .cancel)
        #expect(split?.absoluteString == "https://example.com/target")
    }

    @Test func commandShiftIsATabRatherThanASplit() {
        let (tab, delegate) = subject()
        tab.onOpenInNewTab = { _, _ in }
        tab.onOpenInSplit = { _ in Issue.record("command-shift must not split") }

        _ = decide(delegate, tab, action(
            "https://example.com/target", type: .linkActivated, modifiers: [.command, .shift]
        ))
    }

    @Test func modifiersAreIgnoredWhenThePageNavigatesItself() {
        let (tab, delegate) = subject()
        tab.onOpenInNewTab = { _, _ in Issue.record("a redirect must not open a tab") }
        tab.onOpenInSplit = { _ in Issue.record("a redirect must not split") }

        let policy = decide(delegate, tab, action(
            "https://example.com/target", type: .other, modifiers: [.command, .shift]
        ))

        #expect(policy == .allow)
    }

    @Test func aPlainClickJustNavigates() {
        let (tab, delegate) = subject()
        tab.onOpenInNewTab = { _, _ in Issue.record("a plain click must not open a tab") }

        let policy = decide(delegate, tab, action(
            "https://example.com/target", type: .linkActivated
        ))

        #expect(policy == .allow)
    }

    // MARK: - How the visit is recorded

    @Test func aClickedLinkIsRecordedAsALink() {
        let (tab, delegate) = subject()
        _ = decide(delegate, tab, action("https://example.com/a", type: .linkActivated))
        #expect(tab.pendingTransition == .link)
    }

    @Test func aSubmittedFormIsRecordedAsASubmission() {
        let (tab, delegate) = subject()
        _ = decide(delegate, tab, action("https://example.com/a", type: .formSubmitted))
        #expect(tab.pendingTransition == .formSubmit)
    }

    @Test func goingBackIsRecordedAsGoingBack() {
        let (tab, delegate) = subject()
        _ = decide(delegate, tab, action("https://example.com/a", type: .backForward))
        #expect(tab.pendingTransition == .backForward)
    }

    @Test func aReloadIsRecordedAsAReload() {
        let (tab, delegate) = subject()
        _ = decide(delegate, tab, action("https://example.com/a", type: .reload))
        #expect(tab.pendingTransition == .reload)
    }

    @Test func anUnattributableNavigationKeepsTheReasonAlreadyRecorded() {
        let (tab, delegate) = subject()
        _ = decide(delegate, tab, action("https://example.com/a", type: .linkActivated))

        _ = decide(delegate, tab, action("https://example.com/b", type: .other))

        #expect(tab.pendingTransition == .link)
    }

    // MARK: - Extension pages

    private static let base = URL(string: "webkit-extension://abcdef/popup.html")!

    @Test func anExtensionPageMayMoveAroundItsOwnOrigin() {
        let (tab, delegate) = subject(extensionBase: Self.base)
        tab.onNavigationOutsideExtension = { _ in Issue.record("its own origin is not outside") }

        #expect(decide(delegate, tab, action("webkit-extension://abcdef/options.html")) == .allow)
    }

    @Test func anExtensionPageLeavingItsOriginIsHandedBackToTheBrowser() {
        let (tab, delegate) = subject(extensionBase: Self.base)
        var handedBack: URL?
        tab.onNavigationOutsideExtension = { handedBack = $0 }

        let policy = decide(delegate, tab, action("https://example.com/page"))

        #expect(policy == .cancel)
        #expect(handedBack?.absoluteString == "https://example.com/page")
    }

    @Test func anotherExtensionsOriginIsAlsoOutside() {
        let (tab, delegate) = subject(extensionBase: Self.base)
        var handedBack: URL?
        tab.onNavigationOutsideExtension = { handedBack = $0 }

        let policy = decide(delegate, tab, action("webkit-extension://ffffff/popup.html"))

        #expect(policy == .cancel)
        #expect(handedBack != nil)
    }

    @Test func anExtensionPageKeepsItsBlankFrames() {
        let (tab, delegate) = subject(extensionBase: Self.base)
        tab.onNavigationOutsideExtension = { _ in Issue.record("about: is not a destination") }

        #expect(decide(delegate, tab, action("about:blank")) == .allow)
    }

    @Test func anOrdinaryTabHasNoExtensionBoundaryToCross() {
        let (tab, delegate) = subject()
        tab.onNavigationOutsideExtension = { _ in Issue.record("a web tab has no extension origin") }

        #expect(decide(delegate, tab, action("https://example.com/page")) == .allow)
    }
}
