// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct WindowSessionTests {
    private func reopen(_ model: BrowserModel) -> BrowserModel {
        let restored = BrowserModel(windowID: model.windowID, database: model.database)
        restored.restoreSession()
        return restored
    }

    @Test func anUntouchedProfileHasNoWindowToRestore() {
        #expect(BrowserModel.savedWindows(in: .temporary(), includeClosed: true).isEmpty)
    }

    @Test func windowsSaveTheirOwnTabsFoldersAndSplits() throws {
        let database = AppDatabase.temporary()
        let first = BrowserModel(windowID: UUID(), database: database)
        let second = BrowserModel(windowID: UUID(), database: database)
        let left = first.newTab()
        let right = first.newTab()
        let folder = first.createFolder(named: "Work", containing: [left, right])
        first.split(left, with: right, axis: .sideBySide)
        let other = second.newTab()
        _ = second.createFolder(named: "Personal", containing: [other])
        first.saveBlocking()
        second.saveBlocking()
        first.saveBlocking()

        let restoredFirst = reopen(first)
        let restoredSecond = reopen(second)
        #expect(restoredFirst.tabs.map(\.id) == first.tabs.map(\.id))
        #expect(restoredFirst.folders.first?.name == folder.name)
        #expect(restoredFirst.activeSplit?.tabs == [left.id, right.id])
        #expect(restoredSecond.tabs.map(\.id) == [other.id])
        #expect(restoredSecond.folders.first?.name == "Personal")
        #expect(Set(BrowserModel.savedWindows(in: database).map(\.id)) == [first.windowID, second.windowID])
    }

    @Test func anOlderQueuedWriteCannotReopenAClosedWindow() async {
        let database = AppDatabase.temporary()
        let model = BrowserModel(windowID: UUID(), database: database)
        let tab = model.newTab()
        model.saveNow()
        model.markSessionClosed()
        await model.saveChain?.value

        #expect(BrowserModel.savedWindows(in: database).isEmpty)
        #expect(BrowserModel.savedWindows(in: database, includeClosed: true).first?.closedAt != nil)
        let restored = reopen(model)
        #expect(restored.activeTab?.id == tab.id)
        #expect(BrowserModel.savedWindows(in: database).first?.id == model.windowID)
    }

    @Test func anOlderQueuedWriteCannotUndoTheFinalSnapshot() async {
        let database = AppDatabase.temporary()
        let model = BrowserModel(windowID: UUID(), database: database)
        _ = model.newTab()
        model.saveNow()
        _ = model.newTab()
        model.saveBlocking()
        await model.saveChain?.value
        #expect(reopen(model).tabs.count == 2)
    }

    @Test func movingATabPreservesItsPageAndChangesTheOwningCallbacks() async {
        let database = AppDatabase.temporary()
        let source = BrowserModel(windowID: UUID(), database: database)
        let destination = BrowserModel(windowID: UUID(), database: database)
        let tab = source.newTab()
        let view = tab.webView
        _ = source.newTab()
        var transferred = false
        var closed = false
        source.onTabClosed = { _ in closed = true }
        destination.onTabTransferredIn = { moved, oldOwner, oldIndex in
            transferred = moved === tab && oldOwner === source && oldIndex == 1
        }
        source.saveNow()
        destination.saveNow()

        #expect(destination.adoptTab(tab, from: source))
        #expect(destination.activeTab === tab)
        #expect(destination.activeTab?.webView === view)
        #expect(!tab.isClosed)
        #expect(transferred)
        #expect(!closed)
        await destination.saveChain?.value
        #expect(reopen(source).tabs.count == 1)
        #expect(reopen(destination).tabs.map(\.id) == [tab.id])

        tab.onCloseRequested?()
        #expect(destination.tabs.isEmpty)
        #expect(source.tabs.count == 1)
        #expect(!closed)
    }

    @Test func closingTheDestinationBeforeOldQueuedSavesFinishKeepsTheMovedTab() async {
        let database = AppDatabase.temporary()
        let source = BrowserModel(windowID: UUID(), database: database)
        let destination = BrowserModel(windowID: UUID(), database: database)
        let tab = source.newTab()
        source.saveNow()
        destination.saveNow()
        #expect(destination.adoptTab(tab, from: source))
        destination.markSessionClosed()
        await source.saveChain?.value
        await destination.saveChain?.value

        #expect(reopen(source).tabs.isEmpty)
        #expect(reopen(destination).tabs.map(\.id) == [tab.id])
    }

    @Test func aStaleCloseRequestCannotCloseATabTransferredToAnotherWindow() {
        let database = AppDatabase.temporary()
        let source = BrowserModel(windowID: UUID(), database: database)
        let destination = BrowserModel(windowID: UUID(), database: database)
        let tab = source.newTab()
        #expect(destination.adoptTab(tab, from: source))

        source.close(tab)

        #expect(destination.activeTab === tab)
        #expect(!tab.isClosed)
        #expect(source.closedTabs.isEmpty)
        #expect(!source.hasPendingSave)
        #expect(reopen(destination).tabs.map(\.id) == [tab.id])
    }

    @Test func movingATabRequiresOpenSourceAndDestinationSessions() {
        let database = AppDatabase.temporary()
        let source = BrowserModel(windowID: UUID(), database: database)
        let destination = BrowserModel(windowID: UUID(), database: database)
        let sourceTab = source.newTab()
        let destinationTab = destination.newTab()
        destination.markSessionClosed()

        #expect(!destination.adoptTab(sourceTab, from: source))
        #expect(!source.adoptTab(destinationTab, from: destination))
        #expect(source.activeTab === sourceTab)
        #expect(destination.activeTab === destinationTab)
        #expect(!sourceTab.isClosed)
        #expect(!destinationTab.isClosed)
        #expect(reopen(destination).tabs.map(\.id) == [destinationTab.id])
    }

    @Test func movingATabRequiresTheSameProfileDatabase() {
        let source = BrowserModel(windowID: UUID(), database: .temporary())
        let destination = BrowserModel(windowID: UUID(), database: .temporary())
        let tab = source.newTab()
        #expect(!destination.adoptTab(tab, from: source))
        #expect(source.tabs.first === tab)
        #expect(destination.tabs.isEmpty)
    }

    @Test func aQueuedSaveCannotRestoreTheOldWindowIDAfterRemapping() async {
        let database = AppDatabase.temporary()
        let original = BrowserModel(windowID: UUID(), database: database)
        let tab = original.newTab()
        original.saveNow()
        original.markSessionClosed()
        let renamedID = UUID()
        #expect(BrowserModel.remapSavedWindow(in: database, from: original.windowID, to: renamedID))
        await original.saveChain?.value

        #expect(BrowserModel.savedWindows(in: database).isEmpty)
        #expect(BrowserModel.savedWindows(in: database, includeClosed: true).map(\.id) == [renamedID])
        let restored = BrowserModel(windowID: renamedID, database: database)
        restored.restoreSession()
        #expect(restored.tabs.map(\.id) == [tab.id])

        // The original native window may later switch back to this profile with its same ID.
        let reused = BrowserModel(windowID: original.windowID, database: database)
        let newTab = reused.newTab()
        reused.saveBlocking()
        #expect(reopen(reused).tabs.map(\.id) == [newTab.id])
        #expect(reopen(restored).tabs.map(\.id) == [tab.id])
    }

    @Test func remappingRequiresAnExistingSourceAndAnUnusedDestination() {
        let database = AppDatabase.temporary()
        let original = BrowserModel(windowID: UUID(), database: database)
        let other = BrowserModel(windowID: UUID(), database: database)
        let originalTab = original.newTab()
        let otherTab = other.newTab()
        original.saveBlocking()
        other.saveBlocking()

        #expect(!BrowserModel.remapSavedWindow(in: database, from: UUID(), to: UUID()))
        #expect(!BrowserModel.remapSavedWindow(in: database, from: original.windowID, to: other.windowID))
        #expect(reopen(original).tabs.map(\.id) == [originalTab.id])
        #expect(reopen(other).tabs.map(\.id) == [otherTab.id])
        let newID = UUID()
        #expect(BrowserModel.remapSavedWindow(in: database, from: original.windowID, to: newID))
        #expect(!BrowserModel.remapSavedWindow(in: database, from: other.windowID, to: original.windowID))
        #expect(reopen(other).tabs.map(\.id) == [otherTab.id])
        #expect(Set(BrowserModel.savedWindows(in: database).map(\.id)) == [newID, other.windowID])
    }

    @Test func upgradingAnOldSessionKeepsItsTabsInTheFirstWindow() throws {
        let directory = TestFiles.directory.appendingPathComponent("WindowMigration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Linen.sqlite")
        let tabID = UUID()
        let old = try DatabaseQueue(path: url.path)
        try old.write { db in
            try db.execute(sql: """
                CREATE TABLE sessionTab (
                    id BLOB PRIMARY KEY, title TEXT NOT NULL, customTitle TEXT, url TEXT NOT NULL,
                    state BLOB, pinnedURL TEXT, pinnedTitle TEXT, internalPage TEXT,
                    isActive BOOLEAN NOT NULL DEFAULT 0
                );
                CREATE TABLE sessionFolder (
                    id BLOB PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
                    color TEXT NOT NULL, isExpanded BOOLEAN NOT NULL
                );
                CREATE TABLE sessionItem (
                    position INTEGER PRIMARY KEY, tabID BLOB REFERENCES sessionTab(id) ON DELETE CASCADE,
                    folderID BLOB REFERENCES sessionFolder(id) ON DELETE CASCADE,
                    parentID BLOB REFERENCES sessionFolder(id) ON DELETE CASCADE
                );
                """)
            try db.execute(sql: "INSERT INTO sessionTab (id, title, url, isActive) VALUES (?, 'Saved', '', 1)", arguments: [tabID])
            try db.execute(sql: "INSERT INTO sessionItem (position, tabID) VALUES (0, ?)", arguments: [tabID])
        }
        let database = AppDatabase(at: url)
        #expect(!database.isEphemeral)
        #expect(BrowserModel.savedWindows(in: database).map(\.id) == [BrowserModel.legacyWindowID])
        let migratedID = UUID()
        #expect(BrowserModel.remapSavedWindow(in: database, from: BrowserModel.legacyWindowID, to: migratedID))
        #expect(BrowserModel.savedWindows(in: database).map(\.id) == [migratedID])
        let model = BrowserModel(windowID: migratedID, database: database)
        model.restoreSession()
        #expect(model.tabs.map(\.id) == [tabID])
        let additional = BrowserModel(windowID: UUID(), database: database)
        additional.restoreSession()
        #expect(additional.tabs.isEmpty)
    }
}
