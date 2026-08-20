// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// One meaning per typed string, whichever field it lands in: the palette,
/// the address bar and the start page's ask all draw from these.
@MainActor
struct OmniboxTests {
    /// The mode, pinned for the length of one test. Every test that cares
    /// states which side it is on, "off" included - that is not something to
    /// assume just because it is the default.
    ///
    /// Through `Omnibox`'s task-local rather than by writing the setting:
    /// writing made every test here share one switch, so under parallel
    /// execution the "off" and "on" tests answered each other's question -
    /// and it reached into the developer's own live preference.
    private func agentOnly<T>(_ on: Bool = true, _ body: () throws -> T) rethrows -> T {
        try Omnibox.$agentOnlyForTesting.withValue(on) {
            try body()
        }
    }

    @Test func aHostIsAPlaceAndProseIsAQuestion() {
        #expect(Omnibox.location(for: "example.com") != nil)
        #expect(Omnibox.location(for: "what is a monad") == nil)
    }

    @Test func aFullURLKeepsItsSchemeAndABareHostGetsHTTPS() {
        #expect(Omnibox.location(for: "http://example.com/a")?.scheme == "http")
        #expect(Omnibox.location(for: "example.com")?.absoluteString == "https://example.com")
    }

    @Test func returnGoesToAPlace() throws {
        var opened: URL?
        let item = try #require(Omnibox.searchItem(for: "example.com") { opened = $0 })

        #expect(item.kind == .go)
        item.run()
        #expect(opened?.absoluteString == "https://example.com")
    }

    @Test func returnSearchesProse() throws {
        try agentOnly(false) {
            var opened: URL?
            let item = try #require(Omnibox.searchItem(for: "weather tomorrow") { opened = $0 })

            #expect(item.kind == .search)
            #expect(item.detail.contains(Omnibox.engineName))
            item.run()
            let url = try #require(opened)
            #expect(url == SearchURLBuilder.searchURL(for: "weather tomorrow"))
        }
    }

    @Test func anEmptyQueryOffersNoSuggestions() {
        #expect(Omnibox.topSection(query: "   ") { _ in } == nil)
        #expect(Omnibox.phrasesSection(query: "   ", phrases: ["weather"], limit: 3) { _ in } == nil)
    }

    @Test func phrasesBecomeRowsUnderTheEnginesHeader() {
        agentOnly(false) {
            let section = Omnibox.phrasesSection(
                query: "weath",
                phrases: ["weather", "weather tomorrow"],
                limit: 3
            ) { _ in }

            #expect(section?.items.count == 2)
            #expect(section?.title.contains(Omnibox.engineName) == true)
            #expect(section?.items.allSatisfy { $0.kind == .phrase } == true)
        }
    }

    @Test func theEnginesGuessesAreCappedByTheCaller() {
        agentOnly(false) {
            let section = Omnibox.phrasesSection(
                query: "weath",
                phrases: (0..<9).map { "weather \($0)" },
                limit: 3
            ) { _ in }

            #expect(section?.items.count == 3)
            #expect(Omnibox.phrasesSection(query: "weath", phrases: [], limit: 3) { _ in } == nil)
            #expect(Omnibox.phrasesSection(query: "weath", phrases: ["weather"], limit: 0) { _ in } == nil)
        }
    }

    @Test func historyRowsNameTheAddressTheWayAPersonReadsItBack() throws {
        let store = HistoryStore(database: .temporary())
        store.record(url: "https://www.example.com/deep/page", title: "A page")

        let section = try #require(Omnibox.historySection(
            query: "page", store: store, limit: 6
        ) { _ in })
        // No scheme and no `www.`, but the path stays: two pages on one site
        // are otherwise the same row twice.
        #expect(section.items.first?.detail == "example.com/deep/page")
        // And the row wears the site's own mark rather than a clock.
        #expect(section.items.first?.iconHost == "example.com")
    }

    @Test func aTrailingSlashIsNotAPath() throws {
        let store = HistoryStore(database: .temporary())
        store.record(url: "https://example.com/", title: "A home page")

        let section = try #require(Omnibox.historySection(
            query: "home", store: store, limit: 6
        ) { _ in })
        #expect(section.items.first?.detail == "example.com")
    }

    @Test func theSiteItselfOutranksAPageBuriedOnIt() throws {
        let store = HistoryStore(database: .temporary())
        // Recorded oldest first, so the deep pages are the *recent* ones: the
        // store would hand those back first, and relevance has to overrule it.
        store.record(url: "https://nike.com", title: "Nike UK")
        store.record(url: "https://nike.com/gb/t/pegasus-42-shoes-VNFFbZDe/IB1881-602", title: "Nike Pegasus 42")
        store.record(url: "https://nike.com/gb/t/alphafly-3-shoes-c0BiSuME/FD8315-800", title: "Nike Alphafly 3")

        let section = try #require(Omnibox.historySection(
            query: "ni", store: store, limit: 2
        ) { _ in })
        #expect(section.items.count == 2)
        #expect(section.items.first?.detail == "nike.com")
    }

    @Test func aNameThatStartsWithWhatWasTypedBeatsOneThatMerelyContainsIt() {
        let starts = Omnibox.relevance(title: "Nike UK", address: "nike.com", for: "ni")
        let contains = Omnibox.relevance(title: "Sunni Gear", address: "gear.example.com", for: "ni")
        #expect(starts > contains)
    }

    // MARK: - Tabs already open

    @Test func anOpenTabIsOfferedAsSomewhereToSwitchTo() throws {
        let tab = BrowserTab()
        tab.title = "Example Domain"
        tab.urlString = "https://example.com/page"

        let section = try #require(
            Omnibox.tabsSection(query: "example", tabs: [tab], limit: 3) { _ in }
        )
        #expect(section.title == "Switch to Tab")
        // The row says so on its own line: one that looks like history but
        // steals focus to another tab is a surprise every time.
        #expect(section.items.first?.detail.contains("Opened Tab") == true)
        #expect(section.items.first?.detail.contains("example.com") == true)
        #expect(section.items.first?.kind == .tab)
    }

    @Test func aTabIsFoundByItsAddressAsWellAsItsName() throws {
        let tab = BrowserTab()
        tab.title = "Something else entirely"
        tab.urlString = "https://example.com/page"

        #expect(Omnibox.tabsSection(query: "example.com", tabs: [tab], limit: 3) { _ in } != nil)
        #expect(Omnibox.tabsSection(query: "unrelated", tabs: [tab], limit: 3) { _ in } == nil)
    }

    @Test func theRowReturnRunsSitsAloneAndUnheaded() throws {
        agentOnly(false) {
            let section = Omnibox.topSection(query: "example.com") { _ in }
            // No heading: the top hit sits above the groups, not inside one,
            // so reordering what follows can never move it.
            #expect(section?.title.isEmpty == true)
            #expect(section?.items.count == 1)
        }
    }

    /// ⌘-click is how every browser opens a link beside the page it is on, so
    /// the palette offers the same destination twice: here, and in a new tab.
    @Test func theTopRowOffersANewTabAndCommandClickTakesIt() throws {
        try agentOnly(false) {
            var here: [URL] = []
            var beside: [URL] = []
            let section = try #require(Omnibox.topSection(
                query: "example.com",
                openInNewTab: { beside.append($0) },
                open: { here.append($0) }
            ))

            #expect(section.items.map(\.id) == ["omnibox-go", "omnibox-new-tab"])
            #expect(section.items[1].shortcut == "⇧↩")

            section.items[0].run()
            #expect(here.map(\.absoluteString) == ["https://example.com"])
            #expect(beside.isEmpty)

            let alternate = try #require(section.items[0].alternate)
            alternate()
            section.items[1].run()
            #expect(beside.map(\.absoluteString) == ["https://example.com", "https://example.com"])
            #expect(here.count == 1)
        }
    }

    /// A typed search gets the same pair, pointed at the engine.
    @Test func aSearchAlsoOffersANewTab() throws {
        try agentOnly(false) {
            var beside: [URL] = []
            let section = try #require(Omnibox.topSection(
                query: "weather tomorrow",
                openInNewTab: { beside.append($0) },
                open: { _ in }
            ))

            #expect(section.items.map(\.id) == ["omnibox-search", "omnibox-new-tab"])
            section.items[1].run()
            #expect(beside == [SearchURLBuilder.searchURL(for: "weather tomorrow")])
        }
    }

    /// Without a second outcome the same gesture still runs the row, rather
    /// than doing nothing at all.
    @Test func aRowWithoutASecondOutcomeKeepsItsOwn() throws {
        try agentOnly(false) {
            let section = try #require(Omnibox.topSection(query: "example.com") { _ in })

            #expect(section.items.map(\.id) == ["omnibox-go"])
            #expect(section.items[0].alternate == nil)
        }
    }

    @Test func anUnmatchedQueryProducesNoHistorySection() {
        let store = HistoryStore(database: .temporary())
        store.record(url: "https://example.com", title: "Something")

        #expect(Omnibox.historySection(query: "unrelated", store: store, limit: 6) { _ in } == nil)
    }

    // MARK: - Off the web

    @Test func offTheWebProseGetsNoSearchRow() {
        agentOnly {
            #expect(Omnibox.searchItem(for: "weather tomorrow") { _ in } == nil)
            #expect(Omnibox.topSection(query: "weather tomorrow") { _ in } == nil)
        }
    }

    /// A link is still a link. This is the half of the setting that isn't
    /// "everything goes to the model".
    @Test func offTheWebAPlaceStillOpens() throws {
        try agentOnly {
            let section = try #require(Omnibox.topSection(query: "example.com") { _ in })
            #expect(section.items.count == 1)
            #expect(section.items.first?.kind == .go)
            // Naming the engine over a row that never touches it would be a
            // lie about where the click goes.
            #expect(section.title.isEmpty)
        }
    }

    /// Completions are queries the engine wrote. Nothing fetches them in
    /// this mode; this is the second lock on the same door.
    @Test func offTheWebLateCompletionsAreStillDropped() {
        agentOnly {
            #expect(Omnibox.phrasesSection(
                query: "example.com",
                phrases: ["example.com login", "example.com pricing"],
                limit: 3
            ) { _ in } == nil)
        }
    }

    /// The fields ask `Omnibox` rather than the setting, so that is the
    /// answer that has to track it - and the pin a test puts on it must not
    /// outlive the test.
    @Test func theModeIsReadOffTheSetting() {
        let before = BrowserSettings.shared.agentOnlyInput
        agentOnly { #expect(Omnibox.isAgentOnly) }
        agentOnly(false) { #expect(!Omnibox.isAgentOnly) }
        #expect(Omnibox.isAgentOnly == before)
        #expect(Omnibox.agentOnlyPlaceholder.isEmpty == false)
    }

    /// Return has to reach the place even when the mode has taken the search
    /// row away - typing a URL is the one thing this mode still does with
    /// the web.
    @Test func offTheWebReturnStillGoesToAPlace() throws {
        try agentOnly {
            var opened: URL?
            let item = try #require(Omnibox.searchItem(for: "example.com") { opened = $0 })
            #expect(item.kind == .go)
            item.run()
            #expect(opened?.absoluteString == "https://example.com")
        }
    }

    /// A scheme the user typed is still honoured: the mode decides whether
    /// prose becomes a search, not what counts as an address.
    @Test func offTheWebAnExplicitSchemeIsKept() throws {
        try agentOnly {
            var opened: URL?
            let item = try #require(Omnibox.searchItem(for: "http://example.com/a") { opened = $0 })
            item.run()
            #expect(opened?.scheme == "http")
        }
    }

    @Test func offTheWebCompletionsLeaveNoSection() {
        agentOnly {
            #expect(Omnibox.phrasesSection(
                query: "weather tomorrow",
                phrases: ["weather"],
                limit: 3
            ) { _ in } == nil)
        }
    }

    /// The half of the setting that isn't about rows: in this mode a typed
    /// query must not leave the machine to be completed. `SearchSuggestions`
    /// reads the same answer the rows do, so the guard cannot drift from
    /// what the field is showing.
    @Test func offTheWebNothingIsSentAwayToBeCompleted() async {
        let suggestions = SearchSuggestions()
        agentOnly {
            // Long enough and prosaic enough that any other guard would let
            // it through - so an empty list here is this one doing the work.
            suggestions.update(for: "weather tomorrow")
        }
        #expect(suggestions.phrases.isEmpty)
    }

    // MARK: - How the keyboard walks the sections

    private func section(_ id: String, _ count: Int) -> OmniboxSection {
        OmniboxSection(
            id: id,
            title: id.capitalized,
            items: (0..<count).map { n in
                OmniboxItem(id: "\(id)-\(n)", kind: .action, title: "\(id) \(n)") {}
            }
        )
    }

    /// Arrowing past either end wraps: up from the first row is how the
    /// keyboard reaches the last one without walking the whole list.
    @Test func arrowingWrapsAtBothEnds() {
        #expect(OmniboxSelection.moved(from: 0, by: -1, resultCount: 4) == 3)
        #expect(OmniboxSelection.moved(from: 3, by: 1, resultCount: 4) == 0)
        #expect(OmniboxSelection.moved(from: 1, by: 2, resultCount: 4) == 3)
        #expect(OmniboxSelection.moved(from: 2, by: 1, resultCount: 0) == 0)
    }

    /// Command-arrow lands on the row that opens the next section, and wraps
    /// the same way.
    @Test func commandArrowJumpsToTheNextSectionsFirstRow() {
        let counts = [section("tabs", 2), section("history", 3)].itemCounts
        #expect(OmniboxSelection.movedBySection(from: 0, by: 1, itemCounts: counts) == 2)
        #expect(OmniboxSelection.movedBySection(from: 1, by: 1, itemCounts: counts) == 2)
        #expect(OmniboxSelection.movedBySection(from: 3, by: -1, itemCounts: counts) == 0)
        #expect(OmniboxSelection.movedBySection(from: 0, by: -1, itemCounts: counts) == 2)
    }

    /// An empty section contributes no row, so it is never a landing place.
    @Test func anEmptySectionIsNeverJumpedTo() {
        let counts = [section("empty", 0), section("tabs", 2), section("history", 1)].itemCounts
        #expect(OmniboxSelection.sectionStarts(itemCounts: counts) == [0, 2])
        #expect(OmniboxSelection.movedBySection(from: 0, by: 1, itemCounts: counts) == 2)
        #expect(OmniboxSelection.movedBySection(from: 0, by: 1, itemCounts: [0, 0]) == 0)
    }

    /// The one helper every "what site is this" row draws from.
    @Test func displayHostStripsTheNoiseAndAdmitsWhenThereIsNone() throws {
        #expect(URL(string: "https://www.example.com/x")?.displayHost == "example.com")
        #expect(URL(string: "https://sub.example.com")?.displayHost == "sub.example.com")
        let hostless = try #require(URL(string: "file:///tmp/x"))
        #expect(hostless.displayHost == nil)
    }
}
