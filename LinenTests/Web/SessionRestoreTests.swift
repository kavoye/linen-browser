// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing

@testable import Linen

/// What a relaunch gets back. The session is rows now, so the arrangement -
/// which tabs, in what order, inside which folder, with which one active -
/// has to survive being taken apart into three tables and put back together.
@MainActor
struct SessionRestoreTests {
    private func reopen(_ database: AppDatabase) -> BrowserModel {
        let model = BrowserModel(database: database)
        model.restoreSession()
        return model
    }

    // MARK: - The schema the session needs

    /// A table the migrator forgets is neither a compile error nor a crash:
    /// the read fails, `restoreSession` swallows it, and the window comes back
    /// empty. That is exactly how a missing `sessionSplit` cost every tab in
    /// the sidebar, so the schema is checked against what the session writes
    /// rather than trusted.
    @Test func theSchemaHoldsEveryTableTheSessionWrites() throws {
        let database = AppDatabase.temporary()
        let tables = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for required in ["sessionTab", "sessionFolder", "sessionItem", "sessionSplitPane"] {
            #expect(tables.contains(required), "the session writes \(required) and the schema has no such table")
        }
    }

    /// A migration is recorded whether or not what it built is still there, so
    /// a database that has been through a build where a table was added and
    /// later renamed sits at "applied" with that table missing - and every
    /// session it holds reads back as nothing. The schema is declared rather
    /// than migrated to, so opening the database puts back whatever it lacks.
    @Test func openingADatabasePutsBackATableItHasLost() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaRepair-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = AppDatabase(at: url)
        try database.writer.write { db in
            try db.execute(sql: "DROP TABLE sessionSplitTree")
        }

        let reopened = AppDatabase(at: url)
        let tables = try reopened.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        #expect(tables.contains("sessionSplitTree"))
    }

    /// Which two tabs were side by side is the one part of a session the
    /// browser can open without. Losing it must never cost the tabs, on the
    /// way in or on the way out.
    @Test func tabsSurviveADatabaseThatCannotHoldSplits() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let left = model.newTab(url: URL(string: "https://a.example/"))
        let right = model.newTab(url: URL(string: "https://b.example/"))
        model.split(left, with: right, axis: .sideBySide)

        // A database from before splits existed - which is every database that
        // has been through a launch of the build before this one.
        try database.writer.write { db in
            try db.execute(sql: "DROP TABLE sessionSplitTree")
        }

        model.saveBlocking()
        let reopened = reopen(database)

        #expect(reopened.tabs.map(\.id) == [left.id, right.id])
        #expect(reopened.splits.isEmpty)
    }

    // MARK: - Splits

    @Test func aGridComesBackWithItsArrangement() {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let topLeft = model.newTab(url: URL(string: "https://a.example/"))
        let topRight = model.newTab(url: URL(string: "https://b.example/"))
        let bottomLeft = model.newTab(url: URL(string: "https://c.example/"))
        let bottomRight = model.newTab(url: URL(string: "https://d.example/"))
        model.split(topLeft, with: topRight, axis: .sideBySide)
        model.insertIntoSplit(bottomLeft, beside: topLeft, edge: .bottom)
        model.insertIntoSplit(bottomRight, beside: topRight, edge: .bottom)
        for seam in SplitLayout(
            grid: model.activeSplit!,
            size: CGSize(width: 1000, height: 800),
            gutter: 6
        ).seams where seam.axis == .sideBySide {
            model.setSplitSeam(seam, containing: topLeft, leading: 0.7, minimum: 0.1)
        }
        model.activeTabID = topRight.id
        model.saveBlocking()

        let reopened = reopen(database)
        let split = reopened.activeSplit

        #expect(split?.tabs == [topLeft.id, bottomLeft.id, topRight.id, bottomRight.id])
        #expect(split?.root.children.first?.share.isApproximately(0.7) == true)
        #expect(split?.isUnderTopBar(topLeft.id) == true)
        #expect(split?.isUnderTopBar(bottomLeft.id) == false)
        #expect(reopened.splitPanes?.map(\.id) == [
            topLeft.id, bottomLeft.id, topRight.id, bottomRight.id,
        ])
    }

    /// A session written before the arrangement became a tree still opens the
    /// way it was left. Without this the first launch on this build would find
    /// a table it no longer reads and quietly open every split as single pages.
    @Test func readsAGridWrittenInTheOlderFlatForm() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let topLeft = model.newTab(url: URL(string: "https://a.example/"))
        let topRight = model.newTab(url: URL(string: "https://b.example/"))
        let below = model.newTab(url: URL(string: "https://c.example/"))
        model.activeTabID = topLeft.id
        model.saveBlocking()

        // Exactly what the build before this one left behind: the trees gone,
        // and one row per pane of a grid of rows.
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sessionSplitTree")
            let grid = UUID()
            for (tab, row, column) in [(topLeft, 0, 0), (topRight, 0, 1), (below, 1, 0)] {
                try db.execute(
                    sql: """
                        INSERT INTO sessionSplitPane
                            (tabID, splitID, rowIndex, columnIndex, rowFraction, columnFraction)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [tab.id, grid, row, column, 0.3, 0.7]
                )
            }
        }

        let reopened = reopen(database)
        let split = try #require(reopened.activeSplit)

        #expect(split.tabs == [topLeft.id, topRight.id, below.id])
        #expect(split.root.children.first?.share.isApproximately(0.3) == true)
        #expect(split.isUnderTopBar(topLeft.id))
        #expect(!split.isUnderTopBar(below.id))
    }

    /// And it is read once. Saving writes the tree and clears the flat rows, so
    /// a later launch cannot fall back to whatever they last said.
    @Test func theOlderFlatFormIsClearedOnceItHasBeenRead() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let left = model.newTab(url: URL(string: "https://a.example/"))
        let right = model.newTab(url: URL(string: "https://b.example/"))
        model.split(left, with: right, axis: .sideBySide)
        model.saveBlocking()

        let over = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM sessionSplitPane") ?? 0
        }
        #expect(over == 0)
    }

    /// Both halves of a restored split are on screen the moment the window
    /// opens, so both have to load. Left deferred, the pane that isn't focused
    /// comes back a blank rectangle beside a real page and stays that way
    /// until it is clicked.
    @Test func everyPaneOfARestoredGridLoads() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let elsewhere = model.newTab(url: URL(string: "https://c.example/"))
        let left = model.newTab(url: URL(string: "https://a.example/"))
        let right = model.newTab(url: URL(string: "https://b.example/"))
        let below = model.newTab(url: URL(string: "https://d.example/"))
        model.split(left, with: right, axis: .sideBySide)
        model.insertIntoSplit(below, beside: left, edge: .bottom)
        model.activeTabID = right.id
        model.saveBlocking()

        let reopened = reopen(database)
        let panes = try #require(reopened.splitPanes)

        #expect(panes.count == 3)
        #expect(panes.allSatisfy { !$0.isDeferred })
        // And only those two: every other tab is still a guess, and each guess
        // costs a WebContent process.
        #expect(try #require(reopened.tab(id: elsewhere.id)).isDeferred)
    }

    /// An extension page's address is only valid while that extension is
    /// loaded, so such a tab is never written down - and a pair naming one
    /// would come back pointing at a page that does not exist.
    @Test func aSplitMissingOneOfItsPagesIsDropped() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let left = model.newTab(url: URL(string: "https://a.example/"))
        let right = model.newTab(url: URL(string: "https://b.example/"))
        model.split(left, with: right, axis: .sideBySide)
        model.saveBlocking()

        // The row survives its tab only because this reaches around the
        // cascade the schema declares; a session written by a build without
        // that cascade would look exactly like this.
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sessionItem WHERE tabID = ?", arguments: [right.id])
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: "DELETE FROM sessionTab WHERE id = ?", arguments: [right.id])
        }

        let reopened = reopen(database)

        #expect(reopened.tabs.map(\.id) == [left.id])
        #expect(reopened.splits.isEmpty)
        #expect(reopened.activeSplit == nil)
    }

    @Test func tabsComeBackInOrderWithTheSameOneActive() {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)

        // `newTab` puts each new tab on top, so this is c, b, a downwards.
        let first = model.newTab(url: URL(string: "https://a.example/"))
        _ = model.newTab(url: URL(string: "https://b.example/"))
        let last = model.newTab(url: URL(string: "https://c.example/"))
        model.activeTabID = first.id
        model.saveBlocking()

        let reopened = reopen(database)

        #expect(reopened.tabs.map(\.urlString) == [
            "https://c.example/",
            "https://b.example/",
            "https://a.example/",
        ])
        #expect(reopened.activeTabID == first.id)
        #expect(reopened.tabs.first?.id == last.id)
    }

    /// Restored tabs start deferred, and the active one is realized on the
    /// way out. Resolving the wrong tab there leaves the page the user is
    /// looking at blank, with a Reload button that cannot fill it - there is
    /// nothing in the view to reload.
    @Test func theActiveTabIsTheOneThatGetsLoaded() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)

        // Deliberately not the topmost tab: that is the one a lookup falls
        // back to when it fails.
        _ = model.newTab(url: URL(string: "https://first.example/"))
        let active = model.newTab(url: URL(string: "https://active.example/"))
        _ = model.newTab(url: URL(string: "https://last.example/"))
        model.activeTabID = active.id
        model.saveBlocking()

        let reopened = reopen(database)
        let restored = try #require(reopened.tabs.first { $0.id == active.id })

        #expect(reopened.activeTabID == active.id)
        #expect(!restored.isDeferred)
        // And the others are left cold, which is what makes a restore cheap.
        let others = reopened.tabs.filter { $0.id != active.id }.map(\.isDeferred)
        #expect(others == [true, true])
    }

    @Test func aTabKeepsItsIdentityAcrossARelaunch() {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.newTab(url: URL(string: "https://example.com/"))
        model.saveBlocking()

        // The agent's traces are filed under the tab id, so an id that
        // changed on restore would strand every one of them.
        #expect(reopen(database).tabs.map(\.id) == [tab.id])
    }

    /// Checked on a tab that is *not* the active one: the active tab is
    /// realized the moment it is restored, and from then on its state is
    /// whatever WebKit re-serializes rather than the bytes that were stored.
    @Test func theBackForwardBlobSurvives() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)

        let background = model.newTab(url: URL(string: "https://background.example/"))
        let active = model.newTab(url: URL(string: "https://active.example/"))
        let state = Data("interaction-state".utf8)
        background.deferRestore(state: state, url: URL(string: "https://background.example/"))
        model.activeTabID = active.id
        model.saveBlocking()

        let reopened = reopen(database)
        let restored = try #require(reopened.tabs.first { $0.id == background.id })
        #expect(restored.isDeferred)
        #expect(restored.sessionState == state)
    }

    @Test func aFolderComesBackWithItsTabsInPlace() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)

        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        let inside = model.newTab(url: URL(string: "https://inside.example/"))
        let alsoInside = model.newTab(url: URL(string: "https://also.example/"))
        let folder = model.createFolder(named: "Work", containing: [inside, alsoInside])
        folder.isExpanded = false
        folder.color = .teal
        model.saveBlocking()

        let reopened = reopen(database)
        let restored = try #require(reopened.folders.first)

        #expect(reopened.folders.count == 1)
        #expect(restored.name == "Work")
        #expect(restored.color == .teal)
        #expect(!restored.isExpanded)

        let urlsInFolder = reopened.tabs(in: restored).map(\.urlString)
        #expect(urlsInFolder == ["https://inside.example/", "https://also.example/"])
        #expect(reopened.tabs.contains { $0.id == loose.id })
    }

    @Test func aPinnedTabComesBackPinnedToTheSamePage() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.newTab(url: URL(string: "https://example.com/"))
        tab.title = "Example"
        model.pin(tab)
        model.saveBlocking()

        let restored = try #require(reopen(database).tabs.first)
        #expect(restored.pinnedURL == tab.pinnedURL)
        #expect(restored.pinnedTitle == tab.pinnedTitle)
    }

    @Test func aClosedTabLeavesNoRowBehind() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        let closed = model.newTab(url: URL(string: "https://closed.example/"))
        model.saveBlocking()

        model.close(closed)
        model.saveBlocking()

        let rows = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT url FROM sessionTab")
        }
        #expect(rows == ["https://kept.example/"])
        #expect(reopen(database).tabs.map(\.id) == [kept.id])
    }

    /// The arrangement most easily lost by a table that only knows a top
    /// level: the outline has to come back at the depth it went down at.
    @Test func nestedFoldersComeBackAtTheSameDepth() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)

        let deep = model.newTab(url: URL(string: "https://deep.example/"))
        let loose = model.newTab(url: URL(string: "https://loose.example/"))
        let inner = model.createFolder(named: "Inner", containing: [deep])
        let outer = model.createFolder(named: "Outer")
        model.move([.folder(inner.id)], into: outer)
        model.saveBlocking()

        let reopened = reopen(database)
        let restoredOuter = try #require(reopened.folders.first { $0.name == "Outer" })
        let restoredInner = try #require(reopened.folders.first { $0.name == "Inner" })

        #expect(reopened.folder(containing: restoredInner) === restoredOuter)
        #expect(reopened.allTabs(in: restoredOuter).map(\.urlString) == ["https://deep.example/"])
        #expect(reopened.tabs(in: restoredOuter).isEmpty)
        #expect(reopened.sidebarItems.contains(.tab(loose.id)))
        #expect(!reopened.sidebarItems.contains(.folder(restoredInner.id)))
    }

    /// The writer skips the blob for a tab that has not navigated, so the
    /// counter it keys off has to actually move when one does.
    @Test func navigatingMarksATabsStateStale() {
        let model = BrowserModel(database: .temporary())
        let tab = model.newTab()
        let before = tab.sessionStateGeneration

        tab.invalidateSessionState()
        #expect(tab.sessionStateGeneration > before)
    }
}

/// Linen's own pages are addresses now, so a relaunch has to put a tab back on
/// the exact one it was showing - down to which page of Settings.
@MainActor
@Suite(.serialized, .boundedWebViews)
struct SystemPageRestoreTests {
    private func reopen(_ database: AppDatabase) -> BrowserModel {
        let model = BrowserModel(database: database)
        model.restoreSession()
        return model
    }

    @Test func aSystemPageComesBackAsItself() {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        _ = model.showHistory()
        model.saveBlocking()

        let reopened = reopen(database)

        #expect(reopened.tabs.count == 1)
        #expect(reopened.tabs.first?.internalPage == .history)
        #expect(reopened.tabs.first?.title == "History")
    }

    @Test func settingsComesBackOnThePageItWasLeftOn() async {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.showSettings()
        tab.load(SystemPages.settingsURL(.extensions))
        #expect(await settled(tab, at: SystemPages.settingsURL(.extensions)))
        model.saveBlocking()

        let reopened = reopen(database)

        let restored = reopened.tabs.first
        #expect(restored?.internalPage == .settings)
        #expect(SystemPages.settingsCategory(of: restored?.urlString ?? "") == .extensions)
    }

    /// The address only reaches the row through a save the navigation asks
    /// for, and a system page's load finishes down a different path.
    @Test func movingBetweenSettingsPagesAsksForASave() async {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.showSettings()
        #expect(await settled(tab, at: BrowserTab.InternalPage.settings.url))
        model.saveBlocking()

        tab.load(SystemPages.settingsURL(.privacy))
        #expect(await settled(tab, at: SystemPages.settingsURL(.privacy)))
        // No explicit save: the navigation itself has to have scheduled one.
        #expect(await waitUntil { model.hasPendingSave })
    }
}
