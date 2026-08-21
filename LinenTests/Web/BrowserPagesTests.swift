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

    // MARK: - History and Downloads

    @Test func historyTakesOverTheBlankTabItWasAskedFrom() {
        let model = makeModel()
        let blank = model.newTab()

        let shown = model.showHistory()

        #expect(shown === blank)
        #expect(model.tabs.count == 1)
        #expect(shown.internalPage == .history)
    }

    @Test func historyOpensItsOwnTabWhenThePageIsWorthKeeping() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)

        let shown = model.showHistory()

        #expect(shown !== reading)
        #expect(model.tabs.count == 2)
        #expect(model.activeTab === shown)
    }

    @Test func askingForHistoryTwiceReturnsToTheSameTab() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        let first = model.showHistory()

        let second = model.showHistory()

        #expect(first === second)
        #expect(model.tabs.count == 2)
    }

    @Test func aPageSlidesInTheFirstTimeItIsOpened() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        let before = model.internalPageMoves

        _ = model.showHistory()

        #expect(model.internalPageMoves == before + 1)
    }

    @Test func askingForAPageThatIsAlreadyOpenDoesNotSlideItInAgain() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        _ = model.showHistory()
        let opened = model.internalPageMoves

        _ = model.showHistory()

        #expect(model.internalPageMoves == opened)
    }

    @Test func returningToAnOpenPageFromTheSidebarDoesNotSlideItInAgain() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        let history = model.showHistory()
        let opened = model.internalPageMoves

        model.activate(reading)
        model.activate(history)

        #expect(model.internalPageMoves == opened)
    }

    @Test func leavingAPageSlidesItBackOut() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        _ = model.showHistory()
        let opened = model.internalPageMoves

        model.dismissInternalPage(.history)

        #expect(model.internalPageMoves == opened + 1)
    }

    @Test func historyAndDownloadsAreSeparatePages() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)

        let history = model.showHistory()
        let downloads = model.showDownloads()

        #expect(history !== downloads)
        #expect(history.internalPage == .history)
        #expect(downloads.internalPage == .downloads)
    }

    @Test func leavingAPageThatOpenedATabClosesItAndGoesBack() {
        let model = makeModel()
        let reading = model.newTab(url: URL(string: "https://example.com/article")!)
        _ = model.showHistory()

        model.dismissInternalPage(.history)

        #expect(model.tabs.count == 1)
        #expect(model.activeTab === reading)
    }

    @Test func leavingAPageThatBorrowedABlankTabReturnsItBlank() {
        let model = makeModel()
        let blank = model.newTab()
        _ = model.showHistory()

        model.dismissInternalPage(.history)

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

    @Test func leavingOnePageLeavesTheOtherAlone() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/article")!)
        let history = model.showHistory()
        _ = model.showDownloads()

        model.dismissInternalPage(.downloads)

        #expect(model.tabs.contains { $0 === history })
        #expect(history.internalPage == .history)
    }

    // MARK: - Keeping a website awake

    @Test func aWebsiteIsRememberedByItsOrigin() {
        let model = makeModel()
        let tab = model.newTab()
        tab.urlString = "https://example.com/some/deep/page?q=1"

        #expect(model.keepActiveOrigin(for: tab) == SitePermissions.origin(for: URL(string: "https://example.com/")))
    }

    @Test func aPageThatIsNotAWebsiteHasNoOriginToRemember() {
        let model = makeModel()
        let tab = model.newTab()

        for address in ["", "about:blank", "file:///tmp/page.html", "data:text/html,hi"] {
            tab.urlString = address
            #expect(model.keepActiveOrigin(for: tab).isEmpty, "\(address)")
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
