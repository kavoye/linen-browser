// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct AgentTurnModelTests {
    @Test func switchingProfilesForgetsEveryConversation() {
        let fixture = Fixture()
        fixture.model.use(fixture.runner)

        fixture.model.forgetEveryConversation()

        #expect(fixture.runner.discardedEverything)
    }

    @Test func runnerAvailabilityAndNameStayTogether() {
        let fixture = Fixture()

        #expect(fixture.model.runnerName == "none")
        fixture.model.use(fixture.runner)
        #expect(fixture.model.runnerName == "Test runner")
        fixture.model.use(nil)
        #expect(fixture.model.runnerName == "none")
    }

    @Test func unavailableRunnerDoesNotCreateATurn() {
        let fixture = Fixture()

        #expect(!fixture.model.run(utterance: "hello"))
        #expect(!fixture.model.isRunning)
        #expect(fixture.browser.ensureCount == 0)
        #expect(fixture.log.begun.isEmpty)
    }

    @Test func browserAdapterCreatesAndMarksTheSessionTab() throws {
        let browser = BrowserModel(database: .temporary())

        #expect(browser.agentContextSummary(mentionedTabIDs: []) == nil)
        let tabID = browser.ensureAgentTabID()
        let tab = try #require(browser.tab(id: tabID))
        #expect(browser.agentContextSummary(mentionedTabIDs: [])?.contains("ACTIVE") == true)

        browser.setAgentWorking(true, inSpace: tabID)
        #expect(tab.isAgentWorking)
        browser.setAgentWorking(false, inSpace: tabID)
        #expect(!tab.isAgentWorking)
    }

    @Test func aTurnLogsTheRawPromptAndSendsLiveTabContext() async throws {
        let fixture = Fixture(context: "[Pages in context: Shoes, Bag]")
        fixture.runner.waitsForRelease = true
        fixture.model.use(fixture.runner)
        var finishedCount = 0
        fixture.model.onTurnFinished = { finishedCount += 1 }

        #expect(fixture.model.run(utterance: "which is cheaper?"))
        try #require(await waitUntil { fixture.runner.runs.count == 1 })
        let run = try #require(fixture.runner.runs.first)

        #expect(run.utterance == "[Pages in context: Shoes, Bag]\nwhich is cheaper?")
        #expect(fixture.log.begun == [
            .init(id: run.task.id, prompt: "which is cheaper?", tabID: fixture.browser.tabID)
        ])
        #expect(fixture.model.activeTask == run.task)
        #expect(fixture.model.activeTabID == fixture.browser.tabID)
        #expect(fixture.model.isRunning)
        #expect(fixture.browser.working == [.init(tabID: fixture.browser.tabID, isWorking: true)])

        fixture.runner.release(run.task.id)
        #expect(await waitUntil { !fixture.model.isRunning })
        #expect(fixture.log.completed == [.init(id: run.task.id, response: "Run 1 finished")])
        #expect(fixture.browser.working.last == .init(tabID: fixture.browser.tabID, isWorking: false))
        #expect(finishedCount == 1)
    }

    @Test func aTurnWithoutTabContextPassesTheUtteranceUnchanged() async {
        let fixture = Fixture()
        fixture.model.use(fixture.runner)

        fixture.model.run(utterance: "open settings")

        #expect(await waitUntil { fixture.runner.runs.count == 1 })
        #expect(fixture.runner.runs.first?.utterance == "open settings")
        #expect(await waitUntil { !fixture.model.isRunning })
    }

    @Test func cancellationEndsTheTraceAndIgnoresLateCompletion() async throws {
        let fixture = Fixture()
        fixture.runner.waitsForRelease = true
        fixture.model.use(fixture.runner)
        var finishedCount = 0
        fixture.model.onTurnFinished = { finishedCount += 1 }

        fixture.model.run(utterance: "keep going")
        try #require(await waitUntil { fixture.runner.runs.count == 1 })
        let task = try #require(fixture.model.activeTask)
        fixture.model.cancel()

        #expect(!fixture.model.isRunning)
        #expect(fixture.log.cancelled == [task.id])
        #expect(fixture.log.completed.isEmpty)
        #expect(fixture.model.reply.text == nil)
        #expect(fixture.browser.working.last == .init(tabID: task.tabID, isWorking: false))

        fixture.runner.release(task.id)
        #expect(await waitUntil { fixture.runner.released.contains(task.id) })
        #expect(fixture.log.completed.isEmpty)
        #expect(fixture.model.reply.text == nil)
        #expect(finishedCount == 0)
    }

    @Test func aNewTurnCancelsTheOldOneWithoutLosingItsOwnState() async throws {
        let fixture = Fixture()
        fixture.runner.waitsForRelease = true
        fixture.model.use(fixture.runner)

        fixture.model.run(utterance: "first")
        try #require(await waitUntil { fixture.runner.runs.count == 1 })
        let first = fixture.runner.runs[0].task
        fixture.model.run(utterance: "second")
        try #require(await waitUntil { fixture.runner.runs.count == 2 })
        let second = fixture.runner.runs[1].task

        #expect(fixture.log.cancelled == [first.id])
        #expect(fixture.model.activeTask == second)
        #expect(fixture.model.reply.text == "Run 2 started")
        fixture.runner.release(first.id)
        #expect(await waitUntil { fixture.runner.released.contains(first.id) })
        #expect(fixture.model.activeTask == second)
        #expect(fixture.model.reply.text == "Run 2 started")

        fixture.runner.release(second.id)
        #expect(await waitUntil { !fixture.model.isRunning })
        #expect(fixture.log.completed == [.init(id: second.id, response: "Run 2 finished")])
    }

    @Test func closingTheTurnTabCancelsWorkAndDiscardsItsSession() async throws {
        let fixture = Fixture()
        fixture.runner.waitsForRelease = true
        fixture.model.use(fixture.runner)

        fixture.model.run(utterance: "research")
        try #require(await waitUntil { fixture.runner.runs.count == 1 })
        let task = try #require(fixture.model.activeTask)

        #expect(fixture.model.closeTab(task.tabID))
        #expect(fixture.log.cancelled == [task.id])
        #expect(fixture.log.removedTabs == [task.tabID])
        #expect(fixture.runner.discardedTabs == [task.tabID])
        #expect(!fixture.model.isRunning)
        fixture.runner.release(task.id)
        #expect(await waitUntil { fixture.runner.released.contains(task.id) })
        #expect(fixture.log.completed.isEmpty)
    }

    @Test func closingAnotherTabLeavesTheCurrentTurnRunning() async throws {
        let fixture = Fixture()
        fixture.runner.waitsForRelease = true
        fixture.model.use(fixture.runner)
        let otherTab = UUID()

        fixture.model.run(utterance: "research")
        try #require(await waitUntil { fixture.runner.runs.count == 1 })
        let task = try #require(fixture.model.activeTask)

        #expect(!fixture.model.closeTab(otherTab))
        #expect(fixture.model.activeTask == task)
        #expect(fixture.log.cancelled.isEmpty)
        #expect(fixture.log.removedTabs == [otherTab])
        #expect(fixture.runner.discardedTabs == [otherTab])
        fixture.runner.release(task.id)
        #expect(await waitUntil { !fixture.model.isRunning })
    }

    private func waitUntil(
        maxSuspensions: Int = 10_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<maxSuspensions {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private struct Fixture {
    let browser: FakeAgentTurnBrowser
    let log = FakeAgentTurnLog()
    let speech = FakeAgentTurnSpeech()
    let runner = FakeAgentRunner()
    let model: AgentTurnModel

    init(context: String? = nil) {
        browser = FakeAgentTurnBrowser(context: context)
        model = AgentTurnModel(browser: browser, log: log, speech: speech)
    }
}

@MainActor
private final class FakeAgentTurnBrowser: AgentTurnBrowsing {
    struct WorkingEvent: Equatable {
        let tabID: UUID
        let isWorking: Bool
    }

    let tabID = UUID()
    var spaceID: UUID?
    var context: String?
    private(set) var ensureCount = 0
    private(set) var working: [WorkingEvent] = []

    init(context: String?) {
        self.context = context
    }

    func ensureAgentTabID() -> UUID {
        ensureCount += 1
        return tabID
    }

    func agentSpaceID(forTab tabID: UUID) -> UUID {
        spaceID ?? tabID
    }

    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        context
    }

    func setAgentWorking(_ isWorking: Bool, inSpace spaceID: UUID) {
        working.append(.init(tabID: spaceID, isWorking: isWorking))
    }
}

@MainActor
private final class FakeAgentTurnLog: AgentTurnLogging {
    struct Begun: Equatable {
        let id: UUID
        let prompt: String
        let tabID: UUID
    }

    struct Completed: Equatable {
        let id: UUID
        let response: String
    }

    struct Moved: Equatable {
        let from: UUID
        let to: UUID
    }

    private(set) var begun: [Begun] = []
    private(set) var completed: [Completed] = []
    private(set) var cancelled: [UUID] = []
    private(set) var removedTabs: [UUID] = []
    private(set) var reassigned: [Moved] = []

    func beginTask(_ prompt: String, tabID: UUID) -> UUID {
        let id = UUID()
        begun.append(.init(id: id, prompt: prompt, tabID: tabID))
        return id
    }

    func completeTask(_ taskID: UUID, response: String) {
        completed.append(.init(id: taskID, response: response))
    }

    func cancelTask(_ taskID: UUID) {
        cancelled.append(taskID)
    }

    func removeTab(_ tabID: UUID) {
        removedTabs.append(tabID)
    }

    func reassign(from tabID: UUID, to newTabID: UUID) {
        reassigned.append(.init(from: tabID, to: newTabID))
    }
}

@MainActor
private final class FakeAgentRunner: AgentRunner {
    struct Run: Equatable {
        let utterance: String
        let task: AgentTaskContext
    }

    let name = "Test runner"
    var waitsForRelease = false
    private(set) var runs: [Run] = []
    private(set) var released: Set<UUID> = []
    private(set) var discardedTabs: [UUID] = []
    private(set) var discardedEverything = false
    private(set) var transferred: [FakeAgentTurnLog.Moved] = []
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    func prepare() {}

    func discardSession(forTab tabID: UUID) {
        discardedTabs.append(tabID)
    }

    func discardAllSessions() {
        discardedEverything = true
    }

    func transferSession(from tabID: UUID, to newTabID: UUID) {
        transferred.append(FakeAgentTurnLog.Moved(from: tabID, to: newTabID))
    }

    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {
        let runNumber = runs.count + 1
        runs.append(.init(utterance: utterance, task: task))
        reply.beginStream()
        reply.update(text: "Run \(runNumber) started")
        if waitsForRelease {
            await withCheckedContinuation { continuations[task.id] = $0 }
        }
        reply.update(text: "Run \(runNumber) finished")
        released.insert(task.id)
        reply.endStream(retainFor: 60)
    }

    func release(_ taskID: UUID) {
        continuations.removeValue(forKey: taskID)?.resume()
    }
}

@MainActor
private final class FakeAgentTurnSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?

    func speak(_ text: String) {}
    func stopSpeaking() {}
}
