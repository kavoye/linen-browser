// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing

@testable import Linen

/// The agent's durable record. Its whole contract is that a tab is the
/// session boundary - activity, usage and conversation never leak between
/// tabs, and closing a tab takes its history with it - and that survives a
/// relaunch.
@MainActor
struct ConversationLogTests {
    /// Each test gets its own database, so nothing here touches the real one
    /// in Application Support.
    private func makeLog() -> (ConversationLog, AppDatabase) {
        let database = AppDatabase.temporary()
        return (ConversationLog(database: database), database)
    }

    /// "Clear browsing data" has to reach this file. A trace names the pages
    /// the agent visited, so history cleared with the traces left behind is a
    /// list of exactly what was cleared.
    @Test func clearAllForgetsEverySessionAndSurvivesARelaunch() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("find me shoes", tabID: tab)
        log.completeTask(task, response: "Here are three.")
        #expect(log.latestTrace(forTab: tab) != nil)

        log.clearAll()
        #expect(log.latestTrace(forTab: tab) == nil)
        #expect(log.traces(forTab: tab).isEmpty)

        // `clearAll` saves synchronously, so a relaunch cannot restore it.
        let reopened = ConversationLog(database: database)
        #expect(reopened.latestTrace(forTab: tab) == nil)
    }

    /// A cleared log must not resurrect a turn that was already in flight
    /// when the user cleared - the same guard `removeTab` relies on.
    @Test func aTurnInFlightWhenClearedDoesNotComeBack() throws {
        let (log, _) = makeLog()

        let tab = UUID()
        let task = log.beginTask("find me shoes", tabID: tab)
        log.clearAll()
        log.completeTask(task, response: "Here are three.")

        #expect(log.latestTrace(forTab: tab) == nil)
    }

    @Test func recordsATurnFromStartToFinish() throws {
        let (log, _) = makeLog()

        let tab = UUID()
        let task = log.beginTask("find me shoes", tabID: tab)
        let step = try #require(log.beginTool(taskID: task, name: "searchWeb", title: "Search"))
        log.completeTool(taskID: task, stepID: step, detail: "three results")
        log.completeTask(task, response: "Here are three.")

        let trace = try #require(log.latestTrace(forTab: tab))
        #expect(trace.state == .completed)
        #expect(trace.response == "Here are three.")
        #expect(trace.finishedAt != nil)
        // The opening "Understanding the request" step is closed out too; a
        // finished turn should have nothing left spinning.
        #expect(trace.steps.allSatisfy { $0.state != .running })
    }

    @Test func survivesARelaunch() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("hello", tabID: tab)
        log.completeTask(task, response: "hi")
        log.recordUsage(tabID: tab, input: 100, cached: 40, output: 20)
        log.saveBlocking()

        let reopened = ConversationLog(database: database)
        #expect(reopened.traces(forTab: tab).count == 1)
        #expect(reopened.latestTrace(forTab: tab)?.response == "hi")
        let usage = reopened.usage(forTab: tab)
        #expect(usage.requestCount == 1)
        #expect(usage.inputTokens == 100)
        #expect(usage.cachedTokens == 40)
        #expect(usage.outputTokens == 20)
    }

    /// A crash mid-turn leaves a `.running` trace on disk. Loading it back as
    /// still-running would show a task spinning forever with nothing behind
    /// it.
    @Test func repairsATurnInterruptedByAQuit() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("interrupted", tabID: tab)
        _ = log.beginTool(taskID: task, name: "navigate", title: "Open example.com")
        log.saveBlocking()

        let reopened = ConversationLog(database: database)
        let trace = try #require(reopened.latestTrace(forTab: tab))
        #expect(trace.state == .cancelled)
        #expect(trace.finishedAt != nil)
        #expect(trace.steps.allSatisfy { $0.state != .running })
        #expect(!reopened.isRunning(onTab: tab))
    }

    @Test func closingATabTakesItsHistoryWithIt() {
        let (log, _) = makeLog()

        let kept = UUID()
        let closed = UUID()
        log.completeTask(log.beginTask("stays", tabID: kept), response: "a")
        log.completeTask(log.beginTask("goes", tabID: closed), response: "b")
        log.recordUsage(tabID: closed, input: 10, cached: 0, output: 5)

        log.removeTab(closed)

        #expect(log.traces(forTab: closed).isEmpty)
        #expect(log.usage(forTab: closed) == .zero)
        #expect(log.traces(forTab: kept).count == 1)
        #expect(!log.hasActivity(forTab: closed))
    }

    /// A turn cancelled as its tab closed can still be unwinding, and it must
    /// not write usage back into the tab that just went away.
    @Test func aDiscardedTabDoesNotAccrueUsageAfterTheFact() {
        let (log, _) = makeLog()

        let tab = UUID()
        log.completeTask(log.beginTask("x", tabID: tab), response: "y")
        log.removeTab(tab)

        log.recordUsage(tabID: tab, input: 999, cached: 0, output: 999)
        log.recordContextEstimate(tabID: tab, tokens: 5000)

        #expect(log.usage(forTab: tab) == .zero)
    }

    /// The repair for a crash between closing a tab and saving the browser
    /// session: records whose tabs no longer exist are dropped at launch.
    @Test func dropsRecordsForTabsThatNoLongerExist() {
        let (log, _) = makeLog()

        let alive = UUID()
        let orphan = UUID()
        log.completeTask(log.beginTask("alive", tabID: alive), response: "a")
        log.completeTask(log.beginTask("orphan", tabID: orphan), response: "b")

        log.retainTabs([alive])

        #expect(log.traces(forTab: orphan).isEmpty)
        #expect(log.traces(forTab: alive).count == 1)
    }

    /// What seeds a rebuilt model session: completed exchanges only, in
    /// order, most recent when limited. A failed or cancelled turn is not
    /// something to remind the model of.
    @Test func seedsOnlyCompletedExchanges() {
        let (log, _) = makeLog()

        let tab = UUID()
        log.completeTask(log.beginTask("one", tabID: tab), response: "1")
        log.failTask(log.beginTask("two", tabID: tab), reason: "network died")
        log.cancelTask(log.beginTask("three", tabID: tab))
        log.completeTask(log.beginTask("four", tabID: tab), response: "4")

        let exchanges = log.exchanges(forTab: tab)
        #expect(exchanges.map(\.prompt) == ["one", "four"])

        let limited = log.exchanges(forTab: tab, limit: 1)
        #expect(limited.map(\.prompt) == ["four"])
    }

    /// A failure ends the turn with its reason as the response, and a
    /// `completeTask` arriving afterwards must not paper over it.
    @Test func aFailedTurnStaysFailed() throws {
        let (log, _) = makeLog()

        let tab = UUID()
        let task = log.beginTask("doomed", tabID: tab)
        log.failTask(task, reason: "Couldn't reach the model provider.")
        log.completeTask(task, response: "")

        let trace = try #require(log.latestTrace(forTab: tab))
        #expect(trace.state == .failed)
        #expect(trace.response == "Couldn't reach the model provider.")
    }

    /// Starting a second turn on a tab whose first is still running cancels
    /// the first - otherwise two traces claim to be running at once and the
    /// activity panel has no way to choose.
    @Test func onlyOneTurnRunsPerTab() throws {
        let (log, _) = makeLog()

        let tab = UUID()
        let first = log.beginTask("first", tabID: tab)
        _ = log.beginTask("second", tabID: tab)

        let firstTrace = try #require(log.traces(forTab: tab).first { $0.id == first })
        #expect(firstTrace.state == .cancelled)
        #expect(log.traces(forTab: tab).filter { $0.state == .running }.count == 1)
    }

    // MARK: - Rows

    /// Steps are their own table now, hanging off the trace by a foreign key.
    /// If the cascade were not there they would pile up, unreachable, for the
    /// life of the database.
    @Test func stepsGoWhenTheirTraceGoes() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("find me shoes", tabID: tab)
        let step = try #require(log.beginTool(taskID: task, name: "searchWeb", title: "Search"))
        log.completeTool(taskID: task, stepID: step, detail: "three results")
        log.completeTask(task, response: "Here are three.")
        log.saveBlocking()

        #expect(try stepCount(in: database) > 0)

        log.removeTab(tab)
        #expect(try stepCount(in: database) == 0)
        #expect(try traceCount(in: database) == 0)
    }

    /// A turn saves on every step. Each save rewrites that trace's steps, so
    /// a turn must not leave a copy of every step it ever had behind it.
    @Test func savingRepeatedlyDoesNotDuplicateSteps() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("go", tabID: tab)
        for name in ["navigate", "readPage", "click"] {
            let step = try #require(log.beginTool(taskID: task, name: name, title: name))
            log.completeTool(taskID: task, stepID: step, detail: "done")
            log.saveNow()
        }
        log.completeTask(task, response: "finished")
        log.saveBlocking()

        let trace = try #require(log.latestTrace(forTab: tab))
        #expect(try stepCount(in: database) == trace.steps.count)
    }

    @Test func aToolStepComesBackWithItsLinks() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("look it up", tabID: tab)
        let step = try #require(log.beginTool(taskID: task, name: "searchWeb", title: "Search"))
        let link = ConversationLog.ActivityLink(
            title: "Example",
            url: try #require(URL(string: "https://example.com/"))
        )
        log.completeTool(taskID: task, stepID: step, detail: "one result", links: [link])
        log.completeTask(task, response: "found it")
        log.saveBlocking()

        let reopened = ConversationLog(database: database)
        let trace = try #require(reopened.latestTrace(forTab: tab))
        let restored = try #require(trace.steps.first { $0.toolName == "searchWeb" })
        #expect(restored.links == [link])
        #expect(restored.detail == "one result")
        // Order is a column, not an accident of how rows came back.
        #expect(trace.steps.map(\.title) == ["Understanding the request", "Search"])
    }

    @Test func clearingLeavesNoStepsBehind() throws {
        let (log, database) = makeLog()

        let tab = UUID()
        let task = log.beginTask("something", tabID: tab)
        _ = log.beginTool(taskID: task, name: "navigate", title: "Open")
        log.completeTask(task, response: "done")
        log.saveBlocking()

        log.clearAll()
        #expect(try stepCount(in: database) == 0)
        #expect(try traceCount(in: database) == 0)
        #expect(try usageCount(in: database) == 0)
    }

    private func stepCount(in database: AppDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agentStep") ?? 0
        }
    }

    private func traceCount(in database: AppDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agentTrace") ?? 0
        }
    }

    private func usageCount(in database: AppDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM agentUsage") ?? 0
        }
    }
}

/// The bounded stand-in for the three `Set<UUID>`s that used to grow for the
/// life of the process.
struct RecentIDsTests {
    @Test func remembersWhatItWasJustTold() {
        var ids = RecentIDs(capacity: 4)
        let id = UUID()
        ids.insert(id)
        #expect(ids.contains(id))
        ids.remove(id)
        #expect(!ids.contains(id))
    }

    @Test func forgetsTheOldestPastCapacity() {
        var ids = RecentIDs(capacity: 3)
        let all = (0..<5).map { _ in UUID() }
        for id in all {
            ids.insert(id)
        }

        #expect(!ids.contains(all[0]))
        #expect(!ids.contains(all[1]))
        #expect(ids.contains(all[2]))
        #expect(ids.contains(all[4]))
    }

    @Test func reinsertingMovesAnIDBackToTheFront() {
        var ids = RecentIDs(capacity: 2)
        let a = UUID(), b = UUID(), c = UUID()
        ids.insert(a)
        ids.insert(b)
        ids.insert(a)   // a is now the most recent, so b is the one to go
        ids.insert(c)

        #expect(ids.contains(a))
        #expect(ids.contains(c))
        #expect(!ids.contains(b))
    }
}
