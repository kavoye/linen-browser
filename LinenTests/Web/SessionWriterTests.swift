// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing

@testable import Linen

/// What reaches the disk between launches. `SessionRestoreTests` covers one
/// save and one restore; these cover the writer that decides *when* a save
/// happens, and the second relaunch, where a session is written back from
/// tabs that were themselves restored.
@MainActor
struct SessionWriterTests {
    private func restoring<T>(_ body: () throws -> T) rethrows -> T {
        let previous = BrowserSettings.shared.startup
        BrowserSettings.shared.startup = .restore
        defer { BrowserSettings.shared.startup = previous }
        return try body()
    }

    private func reopen(_ database: AppDatabase) -> BrowserModel {
        restoring {
            let model = BrowserModel(database: database)
            model.restoreSession()
            return model
        }
    }

    private func storedTabCount(in database: AppDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM sessionTab") ?? 0
        }
    }

    // MARK: - Relaunching twice

    @Test func aSecondRelaunchKeepsEveryTab() {
        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        for index in 0..<5 {
            _ = first.newTab(url: URL(string: "https://example.com/\(index)"))
        }
        first.saveBlocking()
        let opened = first.tabs.map(\.id)

        let second = reopen(database)
        second.saveBlocking()
        let third = reopen(database)

        #expect(second.tabs.map(\.id) == opened)
        #expect(third.tabs.map(\.id) == opened)
    }

    @Test func aTabOpenedAfterARestoreSurvivesTheNextRelaunch() {
        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        _ = first.newTab(url: URL(string: "https://kept.example/"))
        first.saveBlocking()

        let second = reopen(database)
        _ = second.newTab(url: URL(string: "https://added.example/"))
        second.saveBlocking()

        let third = reopen(database)
        #expect(third.tabs.map(\.urlString).sorted() == ["https://added.example/", "https://kept.example/"])
    }

    @Test func foldersSurviveASecondRelaunch() throws {
        let database = AppDatabase.temporary()
        let first = BrowserModel(database: database)
        let inside = first.newTab(url: URL(string: "https://inside.example/"))
        _ = first.createFolder(named: "Work", containing: [inside])
        _ = first.newTab(url: URL(string: "https://loose.example/"))
        first.saveBlocking()

        let second = reopen(database)
        second.saveBlocking()
        let third = reopen(database)
        let folder = try #require(third.folders.first)

        #expect(third.tabs.count == 2)
        #expect(third.tabs(in: folder).map(\.urlString) == ["https://inside.example/"])
    }

    // MARK: - When a save happens

    @Test func theDelayIsCappedSoAStreamOfChangesCannotStarveIt() {
        let debounce = Duration.seconds(2)
        let deadline = Duration.seconds(8)
        func delay(waiting: Duration) -> Duration {
            BrowserModel.saveDelay(waiting: waiting, debounce: debounce, deadline: deadline)
        }

        #expect(delay(waiting: .zero) == debounce)
        #expect(delay(waiting: .seconds(5)) == debounce)
        #expect(delay(waiting: .seconds(7)) == .seconds(1))
        #expect(delay(waiting: .seconds(9)) == .zero)
    }

    /// A page that rewrites its address every few hundred milliseconds - a map
    /// being panned, a feed - used to restart the timer every time and hold
    /// the whole session unwritten for as long as it kept doing it.
    @Test func achangingPageCannotHoldTheSessionUnwritten() async throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        model.saveDebounce = .milliseconds(100)
        model.saveDeadline = .milliseconds(300)
        _ = model.newTab(url: URL(string: "https://busy.example/"))

        for _ in 0..<40 {
            model.scheduleSave()
            try await Task.sleep(for: .milliseconds(25))
        }
        await model.saveChain?.value

        #expect(try storedTabCount(in: database) == 1)
    }

    /// Each save deletes the rows its own snapshot does not name, so a write
    /// that lands out of order takes the tabs opened since with it.
    @Test func savesLandInTheOrderTheyWereTaken() async throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        _ = model.newTab(url: URL(string: "https://first.example/"))

        // Held open so both saves are waiting on the writer at once, which is
        // where the order used to be decided by whichever task woke first.
        database.writer.asyncWriteWithoutTransaction { _ in
            Thread.sleep(forTimeInterval: 0.2)
        }
        model.saveNow()
        _ = model.newTab(url: URL(string: "https://second.example/"))
        model.saveNow()
        await model.saveChain?.value

        #expect(try storedTabCount(in: database) == 2)
    }

    /// The counter that says "this tab's blob is on disk" must not move for a
    /// write that failed, or those tabs come back without their back-forward
    /// list and never write it again.
    @Test func aFailedWriteLeavesTheBlobToBeWrittenAgain() throws {
        let database = AppDatabase.temporary()
        let model = BrowserModel(database: database)
        let tab = model.newTab(url: URL(string: "https://example.com/"))
        model.saveBlocking()
        #expect(model.writtenStateGeneration[tab.id] != nil)

        try database.writer.write { db in
            try db.execute(sql: "DROP TABLE sessionTab")
        }
        model.saveBlocking()

        #expect(model.writtenStateGeneration[tab.id] == nil)
    }
}

/// One copy of Linen owns the session file. A second copy — a debug build
/// beside the installed app, or the app that hosts these tests — used to open
/// the same database and write its own idea of the tabs over it.
struct SessionOwnershipTests {
    @Test func theAppThatHostsTheseTestsKeepsNothing() {
        #expect(!AppDatabase.ownsSession)
        #expect(AppDatabase.shared.isEphemeral)
    }

    @Test func onlyOneHolderAtATime() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLock-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try #require(SessionLock.take(at: url))
        #expect(SessionLock.take(at: url) == nil)

        first.release()
        let second = try #require(SessionLock.take(at: url))
        second.release()
    }
}
