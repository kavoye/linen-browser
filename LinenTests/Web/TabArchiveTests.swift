// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct TabArchiveTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeModel() -> BrowserModel {
        BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: TestFiles.directory
                    .appendingPathComponent("TabArchivePermissions-\(UUID().uuidString).json")
            )
        )
    }

    private func makeTab(in model: BrowserModel, _ url: String, unusedFor age: TimeInterval) -> BrowserTab {
        let tab = model.newTab(url: URL(string: url), activate: false)
        tab.lastActiveAt = now.addingTimeInterval(-age)
        return tab
    }

    // MARK: - Sweeping

    @Test func aTabUnusedPastTheDelayMovesToTheArchive() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let stale = makeTab(in: model, "https://example.com/old", unusedFor: 2 * 86_400)
        stale.title = "Old page"

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 1)

        #expect(!model.tabs.contains { $0 === stale })
        #expect(model.tabArchive.entries.map(\.url) == ["https://example.com/old"])
        #expect(model.tabArchive.entries.first?.title == "Old page")
        #expect(model.tabArchive.entries.first?.archivedAt == now)
        #expect(!model.canReopenClosedTab)
    }

    @Test func aRecentlyUsedTabStays() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let recent = makeTab(in: model, "https://example.com/recent", unusedFor: 3600)

        #expect(model.archiveTabs(unusedFor: .twelveHours, now: now) == 0)
        #expect(model.tabs.contains { $0 === recent })
        #expect(model.tabArchive.entries.isEmpty)
    }

    @Test func neverArchivesNothing() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let stale = makeTab(in: model, "https://example.com/old", unusedFor: 365 * 86_400)

        #expect(model.archiveTabs(unusedFor: .never, now: now) == 0)
        #expect(model.tabs.contains { $0 === stale })
    }

    @Test func theActiveTabStaysHoweverOld() {
        let model = makeModel()
        let active = model.newTab(url: URL(string: "https://example.com/active"))
        active.lastActiveAt = now.addingTimeInterval(-30 * 86_400)

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 0)
        #expect(model.tabs.contains { $0 === active })
    }

    @Test func aPinnedTabStays() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let pinned = makeTab(in: model, "https://example.com/pinned", unusedFor: 30 * 86_400)
        model.pin(pinned)

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 0)
        #expect(model.tabs.contains { $0 === pinned })
    }

    @Test func aTabInAFolderStays() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let filed = makeTab(in: model, "https://example.com/filed", unusedFor: 30 * 86_400)
        let other = makeTab(in: model, "https://example.com/other", unusedFor: 30 * 86_400)
        _ = model.createFolder(named: "Kept", containing: [filed])

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 1)
        #expect(model.tabs.contains { $0 === filed })
        #expect(!model.tabs.contains { $0 === other })
    }

    @Test func aStartPageTabClosesWithoutAnArchiveEntry() {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let blank = model.newTab(activate: false)
        blank.lastActiveAt = now.addingTimeInterval(-30 * 86_400)

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 1)
        #expect(!model.tabs.contains { $0 === blank })
        #expect(model.tabArchive.entries.isEmpty)
    }

    @Test func aPrivateWindowNeverArchives() {
        let model = makeModel()
        model.adopt(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: TestFiles.directory
                    .appendingPathComponent("TabArchivePrivate-\(UUID().uuidString).json")
            ),
            privately: true
        )
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        let stale = makeTab(in: model, "https://example.com/old", unusedFor: 30 * 86_400)

        #expect(model.archiveTabs(unusedFor: .day, now: now) == 0)
        #expect(model.tabs.contains { $0 === stale })
    }

    // MARK: - Use

    @Test func leavingATabMarksItUsed() {
        let model = makeModel()
        let first = model.newTab(url: URL(string: "https://example.com/a"))
        let second = model.newTab(url: URL(string: "https://example.com/b"), activate: false)
        first.lastActiveAt = .distantPast

        model.activate(second)

        #expect(first.lastActiveAt > Date(timeIntervalSinceNow: -60))
        #expect(second.lastActiveAt > Date(timeIntervalSinceNow: -60))
    }

    @Test func lastUseSurvivesARestore() {
        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        _ = first.newTab(url: URL(string: "https://example.com/active"))
        let background = first.newTab(url: URL(string: "https://example.com/old"), activate: false)
        background.lastActiveAt = now
        first.saveBlocking()

        let reopened = BrowserModel(database: database)
        reopened.restoreSession()

        let restored = reopened.tabs.first { $0.id == background.id }
        #expect(restored.map { abs($0.lastActiveAt.timeIntervalSince(now)) < 1 } == true)
    }

    @Test func timeWhileLinenWasClosedDoesNotCount() throws {
        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        _ = first.newTab(url: URL(string: "https://example.com/active"))
        let background = first.newTab(url: URL(string: "https://example.com/old"), activate: false)
        let usedAt = Date(timeIntervalSinceNow: -2 * 86_400)
        background.lastActiveAt = usedAt
        first.saveBlocking()
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE sessionWindow SET lastActiveAt = ?",
                arguments: [Date(timeIntervalSinceNow: -86_400)]
            )
        }

        let reopened = BrowserModel(database: database)
        reopened.restoreSession()

        let restored = try #require(reopened.tabs.first { $0.id == background.id })
        #expect(abs(restored.lastActiveAt.timeIntervalSince(usedAt) - 86_400) < 5)
        #expect(reopened.staleTabs(unusedFor: 1.5 * 86_400).isEmpty)
    }

    // MARK: - Restoring

    @Test func restoringOpensTheTabAndForgetsTheEntry() throws {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/active"))
        model.tabArchive.add([(title: "Old page", url: "https://example.com/old")], at: now)
        let entry = try #require(model.tabArchive.entries.first)

        let tab = model.restore(entry)

        #expect(tab?.urlString == "https://example.com/old")
        #expect(model.activeTabID == tab?.id)
        #expect(model.tabArchive.entries.isEmpty)
    }

    // MARK: - Store

    @Test func archivingAPageAgainKeepsOneEntry() {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Old", url: "https://example.com")], at: now)
        archive.add([(title: "New", url: "https://example.com")], at: now.addingTimeInterval(60))

        #expect(archive.entries.map(\.title) == ["New"])
    }

    @Test func theArchiveKeepsTheNewestEntriesUpToItsCapacity() {
        let archive = TabArchive(database: .temporary())
        let pages = (0...TabArchive.capacity).map { (title: "Page \($0)", url: "https://example.com/\($0)") }
        archive.add(Array(pages.prefix(1)), at: now.addingTimeInterval(-60))
        archive.add(Array(pages.dropFirst()), at: now)

        #expect(archive.entries.count == TabArchive.capacity)
        #expect(!archive.entries.contains { $0.url == "https://example.com/0" })
    }

    @Test func theArchiveSkipsPagesHistoryWouldNotRecord() {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Settings", url: "linen://settings"), (title: "", url: "")], at: now)

        #expect(archive.entries.isEmpty)
    }

    @Test func clearingRecentHistoryClearsRecentArchiveEntries() {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Old", url: "https://example.com/old")], at: now.addingTimeInterval(-7200))
        archive.add([(title: "New", url: "https://example.com/new")], at: now)

        archive.removeEntries(since: now.addingTimeInterval(-3600))

        #expect(archive.entries.map(\.title) == ["Old"])
    }

    @Test func historyRetentionPrunesTheArchive() {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Old", url: "https://example.com/old")], at: now.addingTimeInterval(-2 * 86_400))
        archive.add([(title: "New", url: "https://example.com/new")], at: now)

        archive.prune(retention: .day, now: now)

        #expect(archive.entries.map(\.title) == ["New"])
    }

    // MARK: - Command palette

    @Test func theCommandPaletteFindsAnArchivedTab() throws {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Quarterly report", url: "https://example.com/report")], at: now)
        var restored: TabArchive.Entry?

        let section = try #require(Omnibox.archivedSection(
            query: "quarterly",
            entries: archive.entries,
            limit: 3
        ) { restored = $0 })
        section.items.first?.run()

        #expect(section.items.first?.kind == .archived)
        #expect(restored?.url == "https://example.com/report")
    }

    @Test func theCommandPaletteSkipsArchivedPagesThatAreOpen() {
        let archive = TabArchive(database: .temporary())
        archive.add([(title: "Report", url: "https://example.com/report")], at: now)

        #expect(Omnibox.archivedSection(
            query: "report",
            entries: archive.entries,
            excluding: ["https://example.com/report"],
            limit: 3
        ) { _ in } == nil)
        #expect(Omnibox.archivedSection(query: " ", entries: archive.entries, limit: 3) { _ in } == nil)
    }
}
