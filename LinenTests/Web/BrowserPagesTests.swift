// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct BrowserPagesTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    // MARK: - Reading the address bar

    @Test func anythingWithASchemeIsAPlace() {
        #expect(BrowserModel.looksLikeLocation("https://example.com"))
        #expect(BrowserModel.looksLikeLocation("ftp://example.com"))
        #expect(BrowserModel.looksLikeLocation("about:blank".replacingOccurrences(of: ":", with: "://")))
    }

    @Test func aBareHostIsAPlace() {
        #expect(BrowserModel.looksLikeLocation("example.com"))
        #expect(BrowserModel.looksLikeLocation("example.com/path"))
        #expect(BrowserModel.looksLikeLocation("sub.example.co.uk"))
    }

    @Test func aPhraseWithADotInItIsStillAPhrase() {
        #expect(!BrowserModel.looksLikeLocation("what is swift.org about"))
        #expect(!BrowserModel.looksLikeLocation("hello. world"))
    }

    @Test func proseWithoutADotIsNeverAPlace() {
        #expect(!BrowserModel.looksLikeLocation("swift concurrency"))
        #expect(!BrowserModel.looksLikeLocation("weather"))
        #expect(!BrowserModel.looksLikeLocation(""))
    }

    @Test func aSchemeBeatsEverythingElse() {
        #expect(BrowserModel.looksLikeLocation("https://example.com/a b"))
    }

    // MARK: - What the address bar does with it

    @Test func aTypedHostIsOpenedOverHTTPS() {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("example.com")

        #expect(tab.urlString.hasPrefix("https://example.com"))
    }

    @Test func aTypedURLKeepsTheSchemeItWasGiven() {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("http://example.com/page")

        #expect(tab.urlString.hasPrefix("http://example.com/page"))
    }

    @Test func typedProseIsSearchedFor() {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("swift concurrency")

        #expect(tab.urlString == SearchURLBuilder.searchURL(for: "swift concurrency").absoluteString)
    }

    @Test func surroundingSpaceIsTrimmedBeforeDeciding() {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("   example.com   ")

        #expect(tab.urlString.hasPrefix("https://example.com"))
    }

    @Test func anEmptyAddressBarLoadsNothing() {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("    ")

        #expect(tab.urlString.isEmpty)
    }

    @Test func typingWithNoTabOpenOpensOne() {
        let model = makeModel()
        #expect(model.tabs.isEmpty)

        model.handleAddressInput("example.com")

        #expect(model.tabs.count == 1)
        #expect(model.activeTab?.urlString.hasPrefix("https://example.com") == true)
    }

    // MARK: - Back and forward across Linen's own pages

    /// Every page a tab shows is one entry in one list, so Back needs no
    /// special case for the browser's own pages.
    @Test func backFromAPageOpenedInHistoryReturnsToHistory() async throws {
        let server = try await Self.site()
        let article = try server.url("/one")
        let model = makeModel()
        let tab = model.showHistory()
        #expect(tab.internalPage == .history)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))

        tab.load(article)
        #expect(await settled(tab, at: article))
        #expect(tab.internalPage == nil)
        #expect(tab.canGoBack)

        tab.goBack()
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        #expect(tab.internalPage == .history)
    }

    @Test func goingBackToHistoryLeavesNoPageRunningBehindIt() async throws {
        let server = try await Self.site()
        let model = makeModel()
        let tab = model.showHistory()
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        tab.load(try server.url("/one"))
        #expect(await waitUntil { tab.internalPage == nil })

        tab.goBack()

        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        #expect(tab.urlString == BrowserTab.InternalPage.history.url.absoluteString)
        #expect(!tab.isLoading)
    }

    /// The bug the rewrite was for: a second item opened from History used to
    /// leave a stale mark on the back list, so Back stopped one page short.
    @Test func aSecondItemFromHistoryStillGoesStraightBack() async throws {
        let server = try await Self.site()
        let history = BrowserTab.InternalPage.history.url
        let model = makeModel()
        let tab = model.showHistory()
        #expect(await settled(tab, at: history))

        tab.load(try server.url("/one"))
        #expect(await settled(tab, at: try server.url("/one")))
        tab.goBack()
        #expect(await settled(tab, at: history))

        tab.load(try server.url("/two"))
        #expect(await settled(tab, at: try server.url("/two")))

        tab.goBack()
        #expect(await settled(tab, at: history))
        #expect(tab.internalPage == .history)
    }

    @Test func forwardFromHistoryReturnsToThePageYouOpened() async throws {
        let server = try await Self.site()
        let article = try server.url("/one")
        let history = BrowserTab.InternalPage.history.url
        let model = makeModel()
        let tab = model.showHistory()
        #expect(await settled(tab, at: history))
        tab.load(article)
        #expect(await settled(tab, at: article))
        tab.goBack()
        #expect(await settled(tab, at: history))

        #expect(tab.canGoForward)
        tab.goForward()

        #expect(await settled(tab, at: article))
        #expect(tab.internalPage == nil)
    }

    @Test func aPageOpenedOnItsOwnHasNothingBehindIt() async throws {
        let server = try await Self.site()
        let page = try server.url("/one")
        let model = makeModel()
        let tab = model.newTab(url: page)

        #expect(await settled(tab, at: page))
        #expect(!tab.canGoBack)
    }

    @Test func everySystemPageComesBackTheSameWay() async throws {
        let server = try await Self.site()
        let away = try server.url("/two")
        for page in [BrowserTab.InternalPage.history, .downloads, .releaseNotes, .settings] {
            let model = makeModel()
            let tab = model.newTab(url: page.url)
            #expect(await settled(tab, at: page.url))

            tab.load(away)
            #expect(await settled(tab, at: away))
            #expect(tab.canGoBack)
            tab.goBack()

            #expect(await settled(tab, at: page.url))
            #expect(tab.internalPage == page)
        }
    }

    /// The system pages are addressable, so typing one opens it like any other
    /// address.
    @Test func typingASystemAddressOpensThatPage() async {
        let model = makeModel()
        let tab = model.newTab()

        model.handleAddressInput("linen://settings")

        #expect(await waitUntil { tab.internalPage == .settings })
    }

    /// A real website, served locally. The point of the rewrite is that a
    /// system page and a website are entries in the same list, so the tests
    /// have to cross between the two schemes rather than stay inside one.
    private static func site() async throws -> HTTPFixtureServer {
        try await HTTPFixtureServer.start(routes: [
            "/one": .html("<title>One</title><p>One"),
            "/two": .html("<title>Two</title><p>Two"),
        ])
    }

    // MARK: - Settings

    @Test func settingsOpensInATabOfItsOwn() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        model.activate(reading)

        let shown = model.showSettings()

        #expect(shown.internalPage == .settings)
        #expect(shown.title == "Settings")
        #expect(model.activeTab === shown)
        #expect(shown !== reading, "the page being read is left alone")
        #expect(reading.internalPage == nil)
        #expect(model.tabs.count == 2)
    }

    @Test func settingsReusesItsOwnPageRatherThanOpeningAnother() {
        let model = makeModel()

        let first = model.showSettings()
        _ = model.newTab(url: URL(string: "https://example.com/")!)
        let second = model.showSettings()

        #expect(first === second)
        #expect(model.tabs.count { $0.internalPage == .settings } == 1)
    }

    /// A page that got a tab of its own gives it back on leaving, and the tab
    /// that was being read comes to the front again.
    @Test func leavingSettingsClosesItsTabAndReturns() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        model.activate(reading)

        _ = model.showSettings()
        model.dismissInternalPage(.settings)

        #expect(model.tabs.count == 1)
        #expect(model.activeTab === reading)
    }

    // MARK: - History and Downloads

    @Test func historyTakesOverTheBlankTabItWasAskedFrom() {
        let model = makeModel()
        let blank = model.newTab()

        let shown = model.showHistory()

        #expect(shown === blank)
        #expect(model.tabs.count == 1)
        #expect(shown.internalPage == .history)
    }

    /// Every one of the browser's own pages arrives the same way: over a web
    /// page it gets a tab of its own, and what was being read stays put.
    @Test func aPageOverAWebPageOpensItsOwnTab() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        model.activate(reading)

        let history = model.showHistory()

        #expect(history !== reading, "the page being read is left alone")
        #expect(model.tabs.count == 2)
        #expect(model.activeTab?.internalPage == .history)
        #expect(reading.internalPage == nil)
    }

    @Test func aPageOpensTheSameWayFromTheStartPage() {
        let model = makeModel()
        let start = model.ensureActiveTab()

        let history = model.showHistory()

        #expect(history === start)
        #expect(model.tabs.count == 1)
    }

    @Test func askingForAPageThatIsAlreadyOpenGoesToIt() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        let first = model.showHistory()

        let second = model.showHistory()

        #expect(first === second)
        #expect(model.tabs.count { $0.internalPage == .history } == 1)
    }

    /// A page already open is gone back to rather than loaded again, however
    /// many tabs are in the way.
    @Test func askingForAnOpenPageFromAnotherTabGoesToIt() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        model.activate(reading)
        let history = model.showHistory()
        let other = model.newTab(url: URL(string: "https://example.com/other")!)
        model.activate(other)

        let again = model.showHistory()

        #expect(again === history)
        #expect(model.activeTab === history)
        #expect(other.internalPage == nil, "the tab it was asked from is left alone")
    }

    /// The state the log caught: the browser's own page is showing while the
    /// web view is still busy with a navigation. A `goBack()` issued during a
    /// provisional load is dropped, so the back control did nothing until that
    /// load gave up — tens of seconds later.
    @Test(.boundedWebViews) func backLeavesTheOwnPageWhileTheViewIsStillLoading() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/slow": .html("<title>Slow</title>", delay: 30),
        ])
        let model = makeModel()
        let previous = BrowserSettings.shared.newTab
        BrowserSettings.shared.newTab = .startPage
        defer { BrowserSettings.shared.newTab = previous }

        let tab = model.newTab()
        #expect(await waitUntil { tab.isShowingStartPage })
        model.activeTabID = tab.id
        let history = model.showHistory()
        #expect(history === tab)
        #expect(await waitUntil { tab.internalPage == .history && tab.canGoBack })

        // Busy the view without touching the address, which is the shape the
        // tab is in: showing History, WebKit part-way into something else.
        tab.webView.load(URLRequest(url: try server.url("/slow")))
        #expect(await waitUntil { tab.webView.isLoading })

        model.dismissInternalPage(.history)

        #expect(
            await waitUntil(timeout: .seconds(10)) { model.activeTab?.internalPage == nil },
            "back was dropped while the view was loading"
        )
    }

    /// What the sidebar and the content area disagreed about: the address had
    /// been taken back, but WebKit's list still named History, and the page
    /// stayed on screen until the list caught up seconds later.
    @Test(.boundedWebViews) func aStaleBackForwardListDoesNotKeepAPageOnScreen() async {
        let model = makeModel()
        let tab = model.ensureActiveTab()
        tab.load(BrowserTab.InternalPage.history.url)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        #expect(tab.internalPage == .history)

        // What a back out of History leaves behind: the view is standing on
        // the Start Page with nothing loading, while WebKit's list still names
        // the page that has gone.
        tab.load(SystemPages.start)
        #expect(await waitUntil { tab.isShowingStartPage })

        #expect(tab.urlString.isEmpty, "the tab takes its address back")
        #expect(tab.internalPage == nil, "and does not read the page back off the list")
    }

    /// Back into the page cache fires no navigation callback and leaves
    /// WebKit's list naming the page that has gone. Nothing else is coming to
    /// correct that, so the committed address has to agree with the view as
    /// soon as the view stops loading — the suites that flaked were waiting
    /// on an address that would never arrive.
    @Test(.boundedWebViews) func theCommittedAddressAgreesWithTheViewWhenNothingIsLoading() async {
        let model = makeModel()
        let tab = model.ensureActiveTab()
        tab.load(BrowserTab.InternalPage.history.url)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        tab.load(BrowserTab.InternalPage.settings.url)
        #expect(await settled(tab, at: BrowserTab.InternalPage.settings.url))

        tab.goBack()

        #expect(await waitUntil { !tab.webView.isLoading })
        #expect(tab.committedURL == tab.webView.url, "the list may lag; the view does not")
        #expect(tab.committedURL == BrowserTab.InternalPage.history.url)
    }

    /// Back into the page cache fires no navigation callback, and WebKit's
    /// back-forward list can still name the page being left. The tab has to
    /// take its address back from what it is showing, not from that list.
    @Test(.boundedWebViews) func showingTheStartPageTakesTheAddressBack() async {
        let model = makeModel()
        let tab = model.ensureActiveTab()
        tab.load(SystemPages.start)
        #expect(await settled(tab, at: SystemPages.start))

        // The state a system page leaves behind: an address set by hand, over
        // a web view that is standing on the Start Page.
        tab.urlString = BrowserTab.InternalPage.history.url.absoluteString
        #expect(tab.internalPage == .history)

        tab.refreshChrome()

        #expect(tab.urlString.isEmpty, "the Start Page tab carries no address")
        #expect(tab.internalPage == nil)
    }

    /// Leaving is the same move wherever the page was opened from: the tab
    /// walks back to what it was showing.
    @Test(.boundedWebViews) func backFromAPageReturnsTheTabToWhatItWasShowing() async {
        let model = makeModel()
        let tab = model.ensureActiveTab()
        _ = tab.webView
        #expect(await waitUntil { tab.isShowingStartPage })

        let history = model.showHistory()
        #expect(history === tab)
        #expect(await waitUntil { tab.internalPage == .history })
        #expect(await waitUntil { tab.canGoBack }, "the page it opened over is behind it")

        model.dismissInternalPage(.history)

        #expect(await waitUntil { model.activeTab?.internalPage == nil }, "back never left History")
        #expect(model.tabs.count == 1, "the tab walks back rather than closing")
        #expect(model.activeTab === tab)
        #expect(await waitUntil { tab.isShowingStartPage })
    }

    /// Over the Start Page the page walks in, so the Start Page is behind it.
    /// Over a web page it starts a tab of its own, so it has nothing behind
    /// it, and leaving closes that tab and returns to the page being read.
    @Test(.boundedWebViews) func whatIsBehindThePageDependsOnWhereItOpened() async throws {
        let server = try await Self.site()

        let fromHome = makeModel()
        let home = fromHome.ensureActiveTab()
        _ = home.webView
        #expect(await waitUntil { home.isShowingStartPage })
        _ = fromHome.showHistory()
        #expect(await settled(home, at: BrowserTab.InternalPage.history.url))
        #expect(home.canGoBack, "the Start Page is behind it")

        let fromPage = makeModel()
        let reading = fromPage.newTab(url: try server.url("/one"))
        fromPage.activate(reading)
        #expect(await settled(reading, at: try server.url("/one")))
        let history = fromPage.showHistory()
        #expect(history !== reading)
        #expect(await settled(history, at: BrowserTab.InternalPage.history.url))
        #expect(!history.canGoBack, "a fresh tab has nothing behind it")

        fromPage.dismissInternalPage(.history)
        #expect(fromPage.tabs.count == 1)
        #expect(fromPage.activeTab === reading)
    }

    /// A page that was the first thing a tab ever showed has nothing to walk
    /// back to, so leaving hands that tab to the Start Page. Closing it would
    /// take a window with one tab down to nothing.
    @Test(.boundedWebViews) func leavingAPageWithNothingBehindItGoesHome() async {
        let model = makeModel()
        let tab = model.newTab(url: BrowserTab.InternalPage.history.url)
        model.activate(tab)
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        #expect(!tab.canGoBack, "nothing behind it")

        model.dismissInternalPage(.history)

        #expect(await waitUntil { tab.isShowingStartPage })
        #expect(model.tabs.count == 1, "the tab survives")
        #expect(model.activeTab === tab)
        #expect(tab.internalPage == nil)
    }

    /// Only a blank or start-page tab is taken over. A tab already showing
    /// one of the browser's pages keeps it; the next page gets its own tab.
    @Test(.boundedWebViews) func aSecondPageOpensItsOwnTabToo() async {
        let model = makeModel()
        let tab = model.ensureActiveTab()
        _ = tab.webView
        #expect(await waitUntil { tab.isShowingStartPage })

        let history = model.showHistory()
        #expect(await settled(tab, at: BrowserTab.InternalPage.history.url))
        let downloads = model.showDownloads()

        #expect(history !== downloads, "History keeps its tab")
        #expect(model.tabs.count == 2)
        #expect(model.activeTab === downloads)
        #expect(history.internalPage == .history)

        model.dismissInternalPage(.downloads)

        #expect(model.tabs.count == 1)
        #expect(model.activeTab === history)
    }

    @Test func leavingAPageThatBorrowedABlankTabReturnsItBlank() async {
        let model = makeModel()
        let blank = model.newTab()
        #expect(await settled(blank, at: SystemPages.start))

        _ = model.showHistory()
        #expect(await settled(blank, at: BrowserTab.InternalPage.history.url))

        model.dismissInternalPage(.history)
        #expect(await settled(blank, at: SystemPages.start))

        #expect(model.tabs.count == 1)
        #expect(model.tabs.first === blank)
        #expect(blank.internalPage == nil)
        #expect(blank.title == BrowserTab.placeholderTitle)
    }

    @Test func leavingAPageNobodyOpenedDoesNothing() {
        let model = makeModel()
        let only = model.newTab(url: URL(string: "https://example.com/article")!)

        model.dismissInternalPage(.history)

        #expect(model.tabs.count == 1)
        #expect(model.tabs.first === only)
    }

    // MARK: - Keeping a website awake

    @Test func aWebsiteIsRememberedByItsOrigin() {
        let model = makeModel()
        let tab = model.newTab()
        tab.urlString = "https://example.com/some/deep/page?q=1"

        #expect(model.siteOrigin(for: tab) == SitePermissions.origin(for: URL(string: "https://example.com/")))
    }

    @Test func aPageThatIsNotAWebsiteHasNoOriginToRemember() {
        let model = makeModel()
        let tab = model.newTab()

        for address in ["", "about:blank", "file:///tmp/page.html", "data:text/html,hi"] {
            tab.urlString = address
            #expect(model.siteOrigin(for: tab).isEmpty, "\(address)")
        }
    }

    @Test func keepingAWebsiteAwakeIsReadBackFromTheSameTab() {
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appending(path: "BrowserPagesTests-\(UUID().uuidString).json")
        )
        let model = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let tab = model.newTab()
        tab.urlString = "https://example.com/page"

        #expect(!model.keepsActive(tab))
        model.setKeepsActive(true, for: tab)
        #expect(model.keepsActive(tab))
    }

    @Test func aTabWithNoWebsiteCannotBeKeptAwake() {
        let permissions = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appending(path: "BrowserPagesTests-\(UUID().uuidString).json")
        )
        let model = BrowserModel(database: .temporary(), sitePermissions: permissions)
        let tab = model.newTab()
        tab.urlString = "about:blank"

        model.setKeepsActive(true, for: tab)

        #expect(!model.keepsActive(tab))
    }

    // MARK: - The tab list the assistant reads

    @Test func anEmptyWindowHasNoTabListToDescribe() {
        #expect(makeModel().contextSummary() == nil)
    }

    @Test func onlyThePagesInContextAreListed() {
        let model = makeModel()
        let background = model.newTab(url: URL(string: "https://example.com/a")!)
        background.title = "Background"
        let front = model.newTab(url: URL(string: "https://other.example/b")!)
        front.title = "Front"

        let summary = model.contextSummary() ?? ""

        #expect(summary.contains("Front"))
        #expect(summary.contains("other.example"))
        #expect(!summary.contains("Background"))
        #expect(!summary.contains("example.com"))
    }

    @Test func theTabInFrontIsMarkedActive() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/a")!)
        let front = model.newTab(url: URL(string: "https://other.example/b")!)
        front.title = "Front"

        let summary = model.contextSummary() ?? ""
        let line = summary.split(separator: "\n").first { $0.contains("Front") } ?? ""

        #expect(line.contains("ACTIVE"))
        #expect(summary.components(separatedBy: "ACTIVE").count == 2)
    }

    @Test func anAttachedTabIsMarkedMentioned() {
        let model = makeModel()
        let attached = model.newTab(url: URL(string: "https://example.com/a")!)
        attached.title = "Attached"
        let other = model.newTab(url: URL(string: "https://other.example/b")!)
        other.title = "Other"

        let summary = model.contextSummary(mentionedTabIDs: [attached.id]) ?? ""
        let line = summary.split(separator: "\n").first { $0.contains("Attached") } ?? ""

        #expect(line.contains("MENTIONED"))
        #expect(!(summary.split(separator: "\n").first { $0.contains("Other") } ?? "").contains("MENTIONED"))
    }

    @Test func mentioningNothingAddsNoInstructionsAboutMentions() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/a")!)

        #expect(model.contextSummary()?.contains("MENTIONED") == false)
    }

    @Test func aBlankTabIsListedAsBlankRatherThanSkipped() {
        let model = makeModel()
        let blank = model.newTab()
        blank.title = "Empty"

        let summary = model.contextSummary() ?? ""

        #expect(summary.contains("Empty"))
        #expect(summary.contains("blank"))
    }

    @Test func contextPagesAreNumberedScreenFirstThenMentioned() {
        let model = makeModel()
        let mentioned = model.newTab(url: URL(string: "https://example.com/a")!)
        mentioned.title = "Bottom"
        let top = model.newTab(url: URL(string: "https://other.example/b")!)
        top.title = "Top"

        let summary = model.contextSummary(mentionedTabIDs: [mentioned.id]) ?? ""

        #expect(summary.contains("1. Top"))
        #expect(summary.contains("2. Bottom"))
    }
}

/// Settings is not one page but twelve, so each one is its own address and
/// Back walks between them like anywhere else.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct SettingsRoutingTests {
    @Test func everyCategoryHasAnAddressThatReadsBack() {
        for category in SettingsCategory.allCases {
            let url = SystemPages.settingsURL(category)
            #expect(BrowserTab.InternalPage(url: url) == .settings)
            #expect(SystemPages.settingsCategory(of: url) ?? .general == category)
        }
    }

    /// General is the page Settings opens on, so it is the bare address rather
    /// than a second one that means the same thing.
    @Test func generalIsTheBareAddress() {
        #expect(SystemPages.settingsURL(.general) == BrowserTab.InternalPage.settings.url)
        #expect(SystemPages.settingsCategory(of: BrowserTab.InternalPage.settings.url) == nil)
    }

    @Test func anAddressOutsideSettingsNamesNoCategory() {
        #expect(SystemPages.settingsCategory(of: BrowserTab.InternalPage.history.url) == nil)
        #expect(SystemPages.settingsCategory(of: "https://example.com/settings/appearance") == nil)
        #expect(SystemPages.settingsCategory(of: "linen://settings/nonsense") == nil)
    }

    @Test func backWalksFromOneSettingsPageToTheOneBefore() async {
        let model = BrowserModel(database: .temporary())
        let tab = model.showSettings()
        #expect(await settled(tab, at: BrowserTab.InternalPage.settings.url))

        tab.load(SystemPages.settingsURL(.appearance))
        #expect(await settled(tab, at: SystemPages.settingsURL(.appearance)))
        #expect(tab.internalPage == .settings)

        tab.load(SystemPages.settingsURL(.extensions))
        #expect(await settled(tab, at: SystemPages.settingsURL(.extensions)))

        tab.goBack()
        #expect(await settled(tab, at: SystemPages.settingsURL(.appearance)))
        #expect(tab.internalPage == .settings)

        tab.goBack()
        #expect(await settled(tab, at: BrowserTab.InternalPage.settings.url))
    }

    /// The address survives the round trip through the row, which is what the
    /// navigator reads to follow a Back.
    @Test func aCategoryAddressIsNotCollapsedToTheBareOne() async {
        let model = BrowserModel(database: .temporary())
        let tab = model.showSettings()
        tab.load(SystemPages.settingsURL(.privacy))

        #expect(await waitUntil { tab.urlString == SystemPages.settingsURL(.privacy).absoluteString })
        #expect(tab.title == "Settings")
    }
}
