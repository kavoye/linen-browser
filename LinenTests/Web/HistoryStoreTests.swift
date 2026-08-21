// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The palette's and omnibox's memory of where the user has been. The
/// contract: revisits float rather than pile up, blank and internal pages
/// never enter, and the retention promise made on the Privacy page holds.
@MainActor
struct HistoryStoreTests {
    /// Each test gets its own database, so nothing here touches the real one
    /// in Application Support.
    private func makeStore() -> (HistoryStore, AppDatabase) {
        let database = AppDatabase.temporary()
        return (HistoryStore(database: database), database)
    }

    @Test func aRevisitFloatsInsteadOfPilingUp() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "First visit")
        store.record(url: "https://example.com/b", title: "Elsewhere")
        store.record(url: "https://example.com/a", title: "Second visit")

        #expect(store.entries.count == 2)
        #expect(store.entries.first?.url == "https://example.com/a")
        #expect(store.entries.first?.title == "Second visit")
    }

    @Test func blankAndInternalPagesNeverEnter() {
        let (store, _) = makeStore()

        store.record(url: "", title: "Nothing")
        store.record(url: "about:blank", title: "Blank")
        store.record(url: "https://linen.local/start", title: "Start page")
        // An extension that replaces the new tab page: a real navigation, to
        // a page that is part of the browser rather than part of the web.
        store.record(
            url: "safari-web-extension://84CF36BF-D3D9-4DF5-AF49-A6FFA34F46DC/newtab.html",
            title: "New Tab"
        )
        store.record(url: "file:///Users/someone/notes.html", title: "Notes")
        store.record(url: "data:text/html,<h1>hi</h1>", title: "Inline")

        #expect(store.entries.isEmpty)
    }

    /// The scheme rule guards the import too, not only live navigation.
    @Test func junkArrivingFromAnImportIsDropped() {
        let (store, _) = makeStore()

        store.merge([
            HistoryStore.Entry(
                url: "safari-web-extension://84CF36BF-D3D9-4DF5-AF49-A6FFA34F46DC/newtab.html",
                title: "New Tab",
                date: .now
            ),
            HistoryStore.Entry(url: "https://example.com", title: "A real page", date: .now),
        ])

        #expect(store.entries.map(\.url) == ["https://example.com"])
    }

    @Test func anUntitledPageIsNamedByItsAddress() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/bare", title: "")
        #expect(store.entries.first?.title == "https://example.com/bare")
    }

    @Test func removingOnePageLeavesTheRestAlone() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "Keep")
        store.record(url: "https://example.com/b", title: "Drop")
        guard let doomed = store.entries.first(where: { $0.url == "https://example.com/b" }) else {
            Issue.record("the entry that was just recorded is missing")
            return
        }

        store.remove(doomed)

        #expect(store.entries.map(\.url) == ["https://example.com/a"])
    }

    @Test func searchMatchesTitleAndURLRegardlessOfCase() {
        let (store, _) = makeStore()

        store.record(url: "https://swift.org/docs", title: "Language Guide")
        store.record(url: "https://example.com", title: "Unrelated")

        #expect(store.search("LANGUAGE").count == 1)
        #expect(store.search("swift.org").count == 1)
        #expect(store.search("nowhere").isEmpty)
    }

    @Test func anEmptyQueryReturnsTheNewestFirstAndHonoursTheLimit() {
        let (store, _) = makeStore()

        for i in 1...8 {
            store.record(url: "https://example.com/\(i)", title: "Page \(i)")
        }

        let results = store.search("", limit: 3)
        #expect(results.count == 3)
        #expect(results.first?.url == "https://example.com/8")
    }

    /// The "last hour" of a clear: everything visited after the cutoff goes,
    /// everything before it stays.
    @Test func clearingSinceADateKeepsWhatCameBefore() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/old", title: "Old")
        let cutoff = Date()
        store.record(url: "https://example.com/new", title: "New")

        store.removeEntries(since: cutoff)
        #expect(store.entries.map(\.url) == ["https://example.com/old"])
    }

    /// Retention is enforced against what is *loaded*, not only what is
    /// recorded: entries persisted last month must not outlive a "keep a
    /// day" promise just because the app was closed in between.
    @Test func pruneDropsEntriesOlderThanTheRetentionChoice() {
        let (store, _) = makeStore()

        store.merge([
            HistoryStore.Entry(
                url: "https://example.com/last-week",
                title: "A week ago",
                date: Date(timeIntervalSinceNow: -3 * 86_400)
            ),
            HistoryStore.Entry(url: "https://example.com/today", title: "Today", date: .now),
        ])
        #expect(store.entries.count == 2)

        store.prune(retention: .day)
        #expect(store.entries.map(\.url) == ["https://example.com/today"])
    }

    @Test func foreverMeansForever() {
        let (store, _) = makeStore()

        store.merge([
            HistoryStore.Entry(
                url: "https://example.com/2020",
                title: "Years back",
                date: Date(timeIntervalSinceNow: -6 * 365 * 86_400)
            ),
        ])
        store.prune(retention: .forever)
        #expect(store.entries.count == 1)
    }

    @Test func historySurvivesARelaunch() {
        let (store, database) = makeStore()

        store.record(url: "https://example.com/kept", title: "Kept")

        let reloaded = HistoryStore(database: database)
        #expect(reloaded.entries.map(\.url) == ["https://example.com/kept"])
    }

    @Test func clearEmptiesEverything() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com", title: "Something")
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(store.search("").isEmpty)
    }

    // MARK: - The table behind the window

    /// The window is what the lists draw; the table is everything. Search
    /// goes to the table, which is the whole point of it being one.
    @Test func searchFindsAPageThatFellOutOfTheWindow() {
        let store = HistoryStore(database: .temporary(), windowSize: 2)

        store.record(url: "https://example.com/needle", title: "Needle")
        store.record(url: "https://example.com/b", title: "Filler B")
        store.record(url: "https://example.com/c", title: "Filler C")

        #expect(store.entries.count == 2)
        #expect(!store.entries.contains { $0.url.hasSuffix("/needle") })
        #expect(store.search("needle").map(\.url) == ["https://example.com/needle"])
    }

    @Test func countIsTheWholeTableNotJustTheWindow() {
        let store = HistoryStore(database: .temporary(), windowSize: 2)

        for i in 1...5 {
            store.record(url: "https://example.com/\(i)", title: "Page \(i)")
        }

        #expect(store.entries.count == 2)
        #expect(store.count == 5)
    }

    @Test func countFollowsRemovalAndRevisits() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "A")
        store.record(url: "https://example.com/b", title: "B")
        // A revisit is the same page, so the count must not move.
        store.record(url: "https://example.com/a", title: "A again")
        #expect(store.count == 2)

        guard let doomed = store.entries.first(where: { $0.url.hasSuffix("/b") }) else {
            Issue.record("the entry that was just recorded is missing")
            return
        }
        store.remove(doomed)
        #expect(store.count == 1)
        #expect(store.count == store.entries.count)
    }

    @Test func revisitsAreCountedRatherThanOverwritten() throws {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "First")
        store.record(url: "https://example.com/a", title: "Second")
        store.record(url: "https://example.com/a", title: "Third")

        let entry = try #require(store.entries.first)
        #expect(entry.visitCount == 3)
        #expect(entry.title == "Third")
    }

    /// A page opened every day should beat one opened once, even when the
    /// once was more recent - that is what the visit count is kept for.
    @Test func searchPutsTheOftenVisitedPageFirst() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/rare", title: "Swift rare")
        for _ in 1...4 {
            store.record(url: "https://example.com/daily", title: "Swift daily")
        }
        store.record(url: "https://example.com/rare", title: "Swift rare")

        #expect(store.search("swift").map(\.url).first == "https://example.com/daily")
    }

    @Test func searchMatchesAPrefixRatherThanOnlyAWholeWord() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "Documentation")

        #expect(store.search("docum").count == 1)
        #expect(store.search("documentation").count == 1)
        #expect(store.search("cumenta").isEmpty)
    }

    @Test func searchBoundsToTheDaysAPhraseNames() {
        let (store, _) = makeStore()
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let lastMonth = calendar.date(byAdding: .day, value: -40, to: now)!

        store.merge([
            HistoryStore.Entry(url: "https://example.com/fresh", title: "Pricing fresh", date: yesterday),
            HistoryStore.Entry(url: "https://example.com/stale", title: "Pricing stale", date: lastMonth),
        ])

        let bounded = HistoryQuery.parse("pricing yesterday", now: now, calendar: calendar)
        #expect(store.search(matching: bounded, limit: 10).map(\.url) == ["https://example.com/fresh"])

        let dateOnly = HistoryQuery.parse("yesterday", now: now, calendar: calendar)
        #expect(store.search(matching: dateOnly, limit: 10).map(\.url) == ["https://example.com/fresh"])

        let unbounded = HistoryQuery.parse("pricing", now: now, calendar: calendar)
        #expect(store.search(matching: unbounded, limit: 10).count == 2)
    }

    @Test func mergeAddsUpVisitsAndTakesTheNewerTitle() throws {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "Live")
        store.merge([
            HistoryStore.Entry(url: "https://example.com/a", title: "Stale", date: .distantPast),
        ])

        let entry = try #require(store.entries.first)
        #expect(entry.visitCount == 2)
        // The older visit must not rename the page.
        #expect(entry.title == "Live")
    }

    // MARK: - Visits

    /// The reason the visit log exists. Clearing "the last hour" used to
    /// delete whole page rows by their *last* visit, so a page opened this
    /// morning and again months ago lost both.
    @Test func clearingSinceADateSpareTheOlderVisitToTheSamePage() throws {
        let (store, _) = makeStore()
        let longAgo = Date(timeIntervalSinceNow: -90 * 24 * 3600)

        store.merge([
            HistoryStore.Entry(url: "https://example.com/a", title: "Ages ago", date: longAgo),
        ])
        let cutoff = Date()
        store.record(url: "https://example.com/a", title: "Just now")

        store.removeEntries(since: cutoff)

        // The page survives, because it was not only visited in the window.
        let entry = try #require(store.entries.first { $0.url == "https://example.com/a" })
        #expect(entry.visitCount == 1)
        #expect(store.visits.count == 1)
        // And what is left is the visit from before the cutoff.
        #expect(store.visits.first?.visitedAt ?? .now < cutoff)
    }

    /// The other half: a page whose every visit falls in the window goes.
    @Test func clearingSinceADateDropsAPageVisitedOnlyInside() {
        let (store, _) = makeStore()
        let cutoff = Date()

        store.record(url: "https://example.com/only", title: "Only inside")
        store.removeEntries(since: cutoff)

        #expect(store.entries.isEmpty)
        #expect(store.visits.isEmpty)
        #expect(store.count == 0)
    }

    @Test func aRevisitIsTwoVisitsAndOneEntry() {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "First")
        store.record(url: "https://example.com/a", title: "Second")

        #expect(store.entries.count == 1)
        #expect(store.visits.count == 2)
        #expect(store.visits.allSatisfy { $0.url == "https://example.com/a" })
    }

    @Test func removingOneVisitLeavesTheOtherAndKeepsThePage() throws {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "First")
        let second = try #require(store.record(url: "https://example.com/a", title: "Second"))

        store.removeVisit(second)

        #expect(store.visits.count == 1)
        let entry = try #require(store.entries.first)
        #expect(entry.visitCount == 1)
    }

    /// Removing the last visit takes the page with it - a page with no
    /// visits is a row nothing can reach.
    @Test func removingTheLastVisitRemovesThePage() throws {
        let (store, _) = makeStore()

        let only = try #require(store.record(url: "https://example.com/a", title: "Only"))
        store.removeVisit(only)

        #expect(store.entries.isEmpty)
        #expect(store.visits.isEmpty)
    }

    @Test func aVisitRemembersHowThePageWasReached() throws {
        let (store, _) = makeStore()

        store.record(url: "https://example.com/a", title: "Typed", transition: .typed)
        store.record(url: "https://example.com/b", title: "Clicked", transition: .link)

        #expect(store.visits.first?.transition == .link)
        #expect(store.visits.last?.transition == .typed)
    }

    /// What a per-URL history cannot answer: which page led to this one.
    @Test func theReferrerChainWalksBackToWhereItStarted() throws {
        let (store, _) = makeStore()

        let search = try #require(
            store.record(url: "https://example.com/search", title: "Search", transition: .typed)
        )
        let result = try #require(
            store.record(
                url: "https://example.com/result",
                title: "Result",
                transition: .link,
                fromVisit: search
            )
        )
        let deeper = try #require(
            store.record(
                url: "https://example.com/deeper",
                title: "Deeper",
                transition: .link,
                fromVisit: result
            )
        )

        let chain = store.referrerChain(to: deeper)
        #expect(chain.map(\.url) == [
            "https://example.com/search",
            "https://example.com/result",
            "https://example.com/deeper",
        ])
    }

    /// A typed address is where a chain starts, whatever the caller passes:
    /// nobody arrived at it from anywhere.
    @Test func aTypedAddressCarriesNoReferrer() throws {
        let (store, _) = makeStore()

        let first = try #require(store.record(url: "https://example.com/a", title: "A"))
        let second = try #require(
            store.record(
                url: "https://example.com/b",
                title: "B",
                transition: .typed,
                fromVisit: first
            )
        )

        #expect(store.referrerChain(to: second).map(\.url) == ["https://example.com/b"])
    }

    /// Pages that predate the visit log keep their count, and get the one
    /// visit that can be proven from what was stored.
    @Test func aPageFromBeforeTheVisitLogGetsOneVisit() throws {
        let (store, _) = makeStore()

        store.merge([
            HistoryStore.Entry(
                url: "https://example.com/a",
                title: "Old",
                visitCount: 12,
                lastVisit: Date(timeIntervalSinceNow: -3600)
            ),
        ])

        #expect(store.entries.first?.visitCount == 12)
        #expect(store.visits.count == 1)
        #expect(store.visits.first?.transition == .imported)
    }

    /// `merge` is what the stage session and any future importer write
    /// through: an older copy of a page must not overwrite the fresh one,
    /// and only genuinely new addresses are counted.
    @Test func mergeKeepsTheNewerVisitAndReportsOnlyNewURLs() {
        let (store, _) = makeStore()
        store.record(url: "https://known.example/", title: "Known")

        let added = store.merge([
            .init(url: "https://known.example/", title: "Stale", date: .distantPast),
            .init(url: "https://new.example/", title: "New", date: Date(timeIntervalSinceNow: -60)),
            .init(url: "file:///etc/hosts", title: "No", date: .now),
        ])

        #expect(added == 1)
        #expect(store.entries.first?.title == "Known")
        #expect(store.entries.map(\.url).contains("https://new.example/"))
        #expect(!store.entries.map(\.url).contains("file:///etc/hosts"))
    }
}
