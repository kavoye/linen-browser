// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// What a brand-new tab reports about itself while it has nothing in it.
///
/// The toolbar appears from `hasNoPageYet`, so anything making an empty tab
/// claim to be loading shows as the bar flashing on and off. It did: a pooled
/// view arrives with the warm-up page still in flight, and the tab's own
/// navigation delegate reported the pool's navigation as its own.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct NewTabChromeTests {
    /// The regression, stated as the thing the user saw: an empty tab must
    /// never pass through a loading state, at any point after it is made.
    @Test func anEmptyTabNeverReportsItselfLoading() async {
        let tab = BrowserTab()

        var everClaimedToLoad = false
        var everLeftTheStartPage = false
        // Well past the warm-up page's own load, sampled finely enough to
        // catch a flicker a person would see.
        for _ in 0..<60 {
            if tab.isLoading {
                everClaimedToLoad = true
            }
            if !tab.hasNoPageYet {
                everLeftTheStartPage = true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        #expect(!everClaimedToLoad, "the pool's warm-up page was reported as the tab loading")
        #expect(!everLeftTheStartPage, "the start page condition flickered, which is the toolbar blinking")
        #expect(tab.urlString.isEmpty)
    }

    /// Several tabs at once is the launch case: the pool only holds a couple
    /// of warm views, so the third onward is built and handed over with its
    /// warm-up load definitely still running.
    @Test func aWholeSessionOfNewTabsStaysQuiet() async {
        let tabs = (0..<5).map { _ in BrowserTab() }

        var flickered = false
        for _ in 0..<40 {
            if tabs.contains(where: { !$0.hasNoPageYet }) {
                flickered = true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(!flickered)
    }

    /// The warm-up page is painted `#101014` so WebKit has something to
    /// rasterize. That colour must never reach the toolbar's tint - the bar
    /// takes its wash from the *site*, and an empty tab has no site.
    @Test func theWarmUpPageNeverTintsTheToolbar() async {
        let tab = BrowserTab()
        for _ in 0..<40 {
            #expect(tab.pageColor == nil, "the pool's blank page washed the toolbar in its own backdrop")
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    // MARK: - …without disabling the flag entirely

    /// The fix narrows what counts as loading; it must not narrow it to
    /// nothing. A real page still moves the tab out of the start-page state
    /// and leaves its address behind.
    @Test func arealPageStillEndsTheStartPageState() async {
        let tab = BrowserTab()
        tab.loadHTML(
            "<!doctype html><html><body><h1>Arrived</h1></body></html>",
            baseURL: URL(string: "https://example.test/page")
        )

        #expect(await waitUntil { !tab.hasNoPageYet }, "a real page must take the tab off the start page")

        // And it settles: the address is kept, and loading ends.
        #expect(await waitUntil { !tab.isLoading })
        #expect(tab.urlString.contains("example.test"))
    }

    /// Loading `about:blank` - which is how a closing tab is silenced - is
    /// not a page either, and must not light the chrome up on the way out.
    @Test func blankingATabIsNotAPageLoad() async {
        let tab = BrowserTab()
        tab.load(URL(string: "about:blank")!)

        for _ in 0..<40 {
            #expect(!tab.isLoading)
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(tab.hasNoPageYet)
    }

    // MARK: - The warm-up page's colour

    /// The warm-up page is what the view *displays* between the start page
    /// leaving and the site's first paint, so it has to follow the appearance
    /// it is shown in. Hardcoding the dark window background was invisible in
    /// dark mode and a black flash across every page opened in light.
    @Test func theWarmUpPageFollowsTheAppearanceItIsShownIn() async throws {
        func renderedBackground(_ appearance: NSAppearance.Name) async throws -> (r: Double, g: Double, b: Double) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(
                frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                configuration: configuration
            )
            webView.appearance = NSAppearance(named: appearance)
            webView.loadHTMLString(WebViewPool.warmUpHTML, baseURL: nil)
            #expect(await PageSettle.untilIdle(webView, timeout: .seconds(30)))

            let css = try #require(
                (try? await webView.evaluateJavaScript(
                    "getComputedStyle(document.documentElement).backgroundColor"
                )) as? String
            )
            let numbers = css
                .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .compactMap(Double.init)
            try #require(numbers.count >= 3)
            return (numbers[0], numbers[1], numbers[2])
        }

        let light = try await renderedBackground(.aqua)
        #expect(light.r > 180, "light appearance must render a light warm-up, got rgb(\(light))")

        let dark = try await renderedBackground(.darkAqua)
        #expect(dark.r < 120, "dark appearance must render a dark warm-up, got rgb(\(dark))")
    }

    /// The backdrop SwiftUI paints behind the web view follows the same
    /// rule as every other piece of page-derived chrome: no real page, no
    /// claim. While the warm-up page holds the view, the backdrop is the
    /// window's own background, never the warm-up's.
    @Test func theBackdropClaimsNothingBeforeARealPage() async {
        let tab = BrowserTab()
        for _ in 0..<40 {
            #expect(tab.canvasColor == nil, "the warm-up page's backdrop leaked into the canvas colour")
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// …and takes the site's colour once there is a site, which is what
    /// keeps a resize gap beside a dark page from flashing white.
    @Test func theBackdropTakesTheSitesColourOnceItArrives() async throws {
        let tab = BrowserTab()
        tab.loadHTML(
            "<!doctype html><html><body style=\"background:#123456\"><p>Here</p></body></html>",
            baseURL: URL(string: "https://example.test/dark")
        )

        #expect(await waitUntil { tab.canvasColor != nil }, "a loaded site must supply the backdrop")
    }

    // MARK: - Getting back to it

    /// The bug, stated as the user saw it: open a new tab, go somewhere, and
    /// Back is dead. The start page is this browser's own view rather than a
    /// document, so WebKit's back list begins at the first real page and has
    /// nothing behind it.
    @Test func backReturnsToTheStartPageATabBeganOn() {
        let tab = BrowserTab()
        tab.urlString = "https://example.com"

        #expect(tab.canGoBack)
        tab.goBack()
        #expect(tab.isShowingStartPage)

        // And it is the oldest thing there is: nothing behind the start page.
        #expect(!tab.canGoBack)
        #expect(tab.canGoForward)

        tab.goForward()
        #expect(!tab.isShowingStartPage)
    }

    /// The start page covers a web view that still holds the last page, so the
    /// row kept reading "GitHub" while the new-tab surface was on screen.
    @Test func theStartPageTakesTheRowBackFromThePageItCovers() {
        let tab = BrowserTab()
        tab.urlString = "https://example.com"
        tab.title = "GitHub - swiftlang/swift-evolution"
        tab.favicon = NSImage(size: NSSize(width: 16, height: 16))

        tab.goBack()

        #expect(tab.isShowingStartPage)
        #expect(tab.title == BrowserTab.placeholderTitle)
        #expect(tab.favicon == nil)
    }

    @Test func goingForwardGivesThePageItsNameBack() {
        let tab = BrowserTab()
        tab.urlString = "https://example.com"
        tab.title = "GitHub - swiftlang/swift-evolution"
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        tab.favicon = icon

        tab.goBack()
        tab.goForward()

        #expect(!tab.isShowingStartPage)
        #expect(tab.title == "GitHub - swiftlang/swift-evolution")
        #expect(tab.favicon === icon)
    }

    /// Typing an address replaces what the start page covered, so the old name
    /// must not come back with it.
    @Test func loadingFromTheStartPageKeepsThePlaceholder() throws {
        let tab = BrowserTab()
        tab.urlString = "https://example.com"
        tab.title = "GitHub - swiftlang/swift-evolution"
        tab.favicon = NSImage(size: NSSize(width: 16, height: 16))
        tab.goBack()

        tab.load(try #require(URL(string: "https://example.org")))

        #expect(!tab.isShowingStartPage)
        #expect(tab.title == BrowserTab.placeholderTitle)
        #expect(tab.favicon == nil)
    }

    /// The start page is not a WebKit history entry, so going back to it never
    /// moved WebKit's index and the next load appended rather than replaced.
    @Test func loadingFromTheStartPageBuriesThePageItCovered() {
        typealias History = BrowserTab.StartPageHistory

        // At GitHub, nothing behind it. Leaving the start page buries it.
        let floor = History.floor(backCount: 0, hasCurrentItem: true)
        #expect(floor == 1)

        // WebKit now holds [GitHub, Apple]; standing on Apple, GitHub is behind.
        #expect(History.reachable(["GitHub"], floor: floor).isEmpty)

        // One more page on: Apple is reachable again, GitHub still is not.
        #expect(History.reachable(["GitHub", "Apple"], floor: floor) == ["Apple"])
    }

    @Test func aTabThatNeverLeftTheStartPageBuriesNothing() {
        typealias History = BrowserTab.StartPageHistory

        #expect(History.floor(backCount: 0, hasCurrentItem: false) == 0)
        #expect(History.reachable(["a", "b"], floor: 0) == ["a", "b"])
    }

    /// A restored session rebuilds the list under the mark.
    @Test func aMarkPastTheEndIsIgnored() {
        #expect(BrowserTab.StartPageHistory.reachable(["a"], floor: 5) == ["a"])
    }

    @Test func aTabOpenedStraightOntoALinkHasNoStartPageBehindIt() {
        let tab = BrowserTab(opensBlank: false)
        tab.urlString = "https://example.com"

        #expect(!tab.canGoBack)
        tab.goBack()
        #expect(!tab.isShowingStartPage, "a tab that never showed a start page must not invent one")
    }

    // MARK: - The address field's rhythm

    /// The new-tab field read lopsided: the mic sat in a 20pt slot, the
    /// trailing icon in 16, with a stray 4pt pad between text and icons. Both
    /// sides of the row now build from `iconSlot` and `controlSpacing` alone,
    /// so an icon's distance to the field edge and to the text is the same
    /// pair of numbers on either side.
    @Test func theAddressFieldsGlyphSlotsAreOneSize() {
        let toolbar = AskSurface.Placement.toolbar
        #expect(toolbar.iconSlot == toolbar.orbSize + 2, "the slot is the mic's own; anything narrower clips the orb")
        // The trailing badges are 16pt ChromeIcons; the shared slot must hold
        // them without clipping.
        #expect(toolbar.iconSlot >= 16)

        let start = AskSurface.Placement.startPage
        #expect(start.iconSlot == start.orbSize + 2)
    }

    @Test func typingAnAddressLeavesTheStartPageAgain() throws {
        let tab = BrowserTab()
        tab.urlString = "https://example.com"
        tab.goBack()
        #expect(tab.isShowingStartPage)

        tab.load(try #require(URL(string: "https://example.org")))
        #expect(!tab.isShowingStartPage)
    }
}
