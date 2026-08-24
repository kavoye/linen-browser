// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// What the agent is looking at when two pages share the window. A split is
/// one place to the person in front of it, so it is one session, one activity
/// trail, and one thing the tab list describes - and both of its pages are
/// readable without switching away from either.
@MainActor
@Suite(.boundedWebViews)
struct AgentSpaceTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    private func split(_ model: BrowserModel) -> (BrowserTab, BrowserTab) {
        let left = model.newTab(url: URL(string: "https://example.com/left"))
        let right = model.newTab(url: URL(string: "https://example.com/right"))
        left.title = "Left page"
        right.title = "Right page"
        model.split(left, with: right, axis: .sideBySide)
        return (left, right)
    }

    // MARK: - The space

    @Test func bothPanesOfASplitNameOneSpace() {
        let model = makeModel()
        let (left, right) = split(model)

        #expect(model.spaceID(of: left.id) == left.id)
        #expect(model.spaceID(of: right.id) == left.id)
        model.activate(right)
        #expect(model.activeSpaceID == left.id)
        #expect(model.spaceTabs(left.id).map(\.id) == [left.id, right.id])
    }

    @Test func aLoneTabIsItsOwnSpace() {
        let model = makeModel()
        let tab = model.newTab(url: URL(string: "https://example.com/alone"))

        #expect(model.spaceID(of: tab.id) == tab.id)
        #expect(model.activeSpaceID == tab.id)
        #expect(model.spaceTabs(tab.id).map(\.id) == [tab.id])
    }

    @Test func removingAPaneReturnsBothToTheirOwnSpaces() {
        let model = makeModel()
        let (left, right) = split(model)

        model.removeFromSplit(right)

        #expect(model.spaceID(of: right.id) == right.id)
        #expect(model.spaceID(of: left.id) == left.id)
    }

    // MARK: - What the model is told

    @Test func theTabListSaysWhichPagesShareTheWindow() throws {
        let model = makeModel()
        let (_, right) = split(model)
        model.activate(right)

        let summary = try #require(model.contextSummary())

        #expect(summary.contains("Left page (example.com) ← ON SCREEN, left"))
        #expect(summary.contains("Right page (example.com) ← ON SCREEN, right, ACTIVE"))
        #expect(summary.contains("Split view: the 2 pages"))
    }

    @Test func aStackedSplitIsDescribedTopAndBottom() throws {
        let model = makeModel()
        let (left, _) = split(model)
        model.setSplitAxis(.stacked, containing: left)

        let summary = try #require(model.contextSummary())

        #expect(summary.contains("ON SCREEN, top"))
        #expect(summary.contains("ON SCREEN, bottom"))
    }

    /// Four is the ceiling, and every one of them is in the space.
    @Test func aGridOfFourIsOneSpaceCountedInReadingOrder() throws {
        let model = makeModel()
        let (left, right) = split(model)
        let third = model.newTab(url: URL(string: "https://example.com/third"))
        let fourth = model.newTab(url: URL(string: "https://example.com/fourth"))
        third.title = "Third page"
        fourth.title = "Fourth page"
        model.insertIntoSplit(third, beside: right, edge: .right)
        model.insertIntoSplit(fourth, beside: third, edge: .right)
        model.activate(third)

        #expect(model.spaceTabs(left.id).map(\.id) == [left.id, right.id, third.id, fourth.id])
        #expect(model.activeSpaceID == left.id)
        #expect(model.spaceID(of: fourth.id) == left.id)

        let summary = try #require(model.contextSummary())
        #expect(summary.contains("Left page (example.com) ← ON SCREEN, pane 1 of 4 from the left"))
        #expect(summary.contains("Third page (example.com) ← ON SCREEN, pane 3 of 4 from the left, ACTIVE"))
        #expect(summary.contains("Split view: the 4 pages"))
    }

    /// One page on screen has no arrangement to explain, so the summary keeps
    /// the shape it always had.
    @Test func oneTabIsDescribedWithoutASplitNote() throws {
        let model = makeModel()
        _ = model.newTab(url: URL(string: "https://example.com/alone"))

        let summary = try #require(model.contextSummary())

        #expect(summary.contains("ACTIVE"))
        #expect(!summary.contains("ON SCREEN"))
        #expect(!summary.contains("Split view"))
    }

    // MARK: - The turn

    @Test func aTurnFromEitherPaneBelongsToTheSpace() async throws {
        let model = makeModel()
        let (left, right) = split(model)
        model.activate(right)

        let log = SpaceLog()
        let turns = AgentTurnModel(browser: model, log: log, speech: SilentSpeech())
        turns.use(SpaceRunner())

        #expect(turns.run(utterance: "compare these two pages"))
        let task = try #require(turns.activeTask)

        #expect(task.tabID == right.id)
        #expect(task.spaceID == left.id)
        #expect(log.begun.first?.tabID == left.id)
        #expect(turns.reply.spaceID == left.id)
        // Both panes wear the working mark, so moving the focus ring between
        // them mid-turn cannot lose it.
        #expect(left.isAgentWorking)
        #expect(right.isAgentWorking)

        for _ in 0..<10_000 where turns.isRunning {
            await Task.yield()
        }
        #expect(!turns.isRunning)
        #expect(!left.isAgentWorking)
        #expect(!right.isAgentWorking)
    }

    // MARK: - Renaming a space

    /// A space is named after the page that leads it, so swapping the panes
    /// renames it. Nothing was closed, so the conversation goes on.
    @Test func rearrangingTheGridCarriesTheConversationWithIt() {
        let model = makeModel()
        let (left, right) = split(model)
        var moves: [String] = []
        model.onSpaceAnchorChanged = { moves.append("\($0)→\($1)") }

        model.swapSplitRow(containing: left)

        #expect(model.spaceID(of: left.id) == right.id)
        #expect(moves == ["\(left.id)→\(right.id)"])
    }

    @Test func closingTheLeadingPaneHandsTheConversationToWhatIsLeft() {
        let model = makeModel()
        let (left, right) = split(model)
        let third = model.newTab(url: URL(string: "https://example.com/third"))
        model.insertIntoSplit(third, beside: right, edge: .right)
        var moves: [String] = []
        model.onSpaceAnchorChanged = { moves.append("\($0)→\($1)") }

        model.close(left)

        #expect(model.spaceID(of: third.id) == right.id)
        #expect(moves == ["\(left.id)→\(right.id)"])
    }

    /// Dissolving a grid, or pulling one page out of it, leaves the name where
    /// it is: the page that had it is still open and still has it.
    @Test func aPageLeavingTheGridRenamesNothing() {
        let model = makeModel()
        let (left, right) = split(model)
        let third = model.newTab(url: URL(string: "https://example.com/third"))
        model.insertIntoSplit(third, beside: right, edge: .right)
        var moves = 0
        model.onSpaceAnchorChanged = { _, _ in moves += 1 }

        model.removeFromSplit(third)
        #expect(moves == 0)

        model.dissolveSplit(containing: left)
        #expect(moves == 0)
    }

    /// The other direction: a page joining a grid is joining that grid's
    /// space, so what it was talking about goes with it - unless the grid is
    /// already talking about something, which `ConversationLog.reassign`
    /// refuses.
    @Test func aPageJoiningAGridBringsItsConversationUnderTheGridsName() {
        let model = makeModel()
        let joining = model.newTab(url: URL(string: "https://example.com/joining"))
        let leader = model.newTab(url: URL(string: "https://example.com/leader"))
        var moves: [String] = []
        model.onSpaceAnchorChanged = { moves.append("\($0)→\($1)") }

        model.split(leader, with: joining, axis: .sideBySide)

        #expect(moves == ["\(joining.id)→\(leader.id)"])
    }

    @Test func aRenameDuringATurnWaitsForItToFinish() async throws {
        let model = makeModel()
        let (left, right) = split(model)

        let log = SpaceLog()
        let runner = SpaceRunner()
        runner.waitsForRelease = true
        let turns = AgentTurnModel(browser: model, log: log, speech: SilentSpeech())
        turns.use(runner)
        #expect(turns.run(utterance: "compare them"))
        let task = try #require(turns.activeTask)
        // The runner registers its continuation on its first suspension; a
        // release before that would resume nothing.
        for _ in 0..<10_000 where runner.started == 0 {
            await Task.yield()
        }

        turns.reassignSpace(from: left.id, to: right.id)
        #expect(log.reassigned.isEmpty)

        runner.release(task.id)
        for _ in 0..<10_000 where turns.isRunning {
            await Task.yield()
        }
        #expect(log.reassigned == [.init(from: left.id, to: right.id)])
        #expect(runner.transferred == [.init(from: left.id, to: right.id)])
        #expect(turns.reply.spaceID == right.id)
    }

    /// Two conversations never become one, so a name already in use turns the
    /// move down.
    @Test func aSpaceThatAlreadyHasATrailIsNotOverwritten() {
        let log = ConversationLog(database: .temporary())
        let one = UUID()
        let other = UUID()
        log.completeTask(log.beginTask("first question", tabID: one), response: "first answer")
        log.recordUsage(tabID: one, input: 10, cached: 0, output: 4)
        log.completeTask(log.beginTask("second question", tabID: other), response: "second answer")

        log.reassign(from: one, to: other)
        #expect(log.traces(forTab: one).count == 1)
        #expect(log.traces(forTab: other).count == 1)

        let empty = UUID()
        log.reassign(from: one, to: empty)
        #expect(log.traces(forTab: one).isEmpty)
        #expect(log.traces(forTab: empty).map(\.prompt) == ["first question"])
        #expect(log.usage(forTab: empty).requestCount == 1)
        #expect(log.usage(forTab: one) == .zero)
    }

    // MARK: - Reading the other pane

    @Test func readPageReachesTheOtherPaneOnScreen() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/departures": .html("<h1>Departure board</h1>"),
            "/arrivals": .html("<h1>Arrivals board</h1>"),
        ])
        let model = makeModel()
        let left = model.newTab(url: try server.url("/departures"))
        let right = model.newTab(url: try server.url("/arrivals"))
        for tab in [left, right] {
            #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
            tab.assistantAccess.persistsAnswers = false
            tab.assistantAccess.pageChanged(url: try server.url())
            tab.assistantAccess.set(.control)
        }
        model.split(left, with: right, axis: .sideBySide)
        model.activate(left)

        let toolkit = AgentToolkit(
            browser: model,
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        )
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: left.id, spaceID: left.id))

        #expect((await toolkit.readPage()).contains("Departure board"))
        #expect((await toolkit.readPage(page: "right")).contains("Arrivals board"))
        #expect((await toolkit.readPage(page: "arrivals")).contains("Arrivals board"))
        #expect((await toolkit.readPage(page: "left")).contains("Departure board"))
        #expect((await toolkit.readPage(page: "second")).contains("Arrivals board"))
        #expect((await toolkit.readPage(page: "the moon")).contains("No page on screen or mentioned matches"))
    }

    /// A grid of four is addressed the same way, by ordinal or by the ends of
    /// the line it stands in.
    @Test func readPageAddressesEveryPaneOfAGridOfFour() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/one": .html("<h1>Board one</h1>"),
            "/two": .html("<h1>Board two</h1>"),
            "/three": .html("<h1>Board three</h1>"),
            "/four": .html("<h1>Board four</h1>"),
        ])
        let model = makeModel()
        var panes: [BrowserTab] = []
        for path in ["/one", "/two", "/three", "/four"] {
            let tab = model.newTab(url: try server.url(path))
            #expect(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
            tab.assistantAccess.persistsAnswers = false
            tab.assistantAccess.pageChanged(url: try server.url())
            tab.assistantAccess.set(.control)
            panes.append(tab)
        }
        model.split(panes[0], with: panes[1], axis: .sideBySide)
        model.insertIntoSplit(panes[2], beside: panes[1], edge: .right)
        model.insertIntoSplit(panes[3], beside: panes[2], edge: .right)
        model.activate(panes[0])

        let toolkit = AgentToolkit(
            browser: model,
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        )
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: panes[0].id, spaceID: panes[0].id))

        #expect(model.splitPanes?.map(\.id) == panes.map(\.id))
        #expect((await toolkit.readPage(page: "third")).contains("Board three"))
        #expect((await toolkit.readPage(page: "4")).contains("Board four"))
        #expect((await toolkit.readPage(page: "right")).contains("Board four"))
        #expect((await toolkit.readPage(page: "/two")).contains("Board two"))
    }
}

@MainActor
private final class SpaceLog: AgentTurnLogging {
    struct Begun: Equatable {
        let prompt: String
        let tabID: UUID
    }

    struct Moved: Equatable {
        let from: UUID
        let to: UUID
    }

    private(set) var begun: [Begun] = []
    private(set) var reassigned: [Moved] = []

    func beginTask(_ prompt: String, tabID: UUID) -> UUID {
        begun.append(.init(prompt: prompt, tabID: tabID))
        return UUID()
    }

    func completeTask(_ taskID: UUID, response: String) {}
    func cancelTask(_ taskID: UUID) {}
    func removeTab(_ tabID: UUID) {}

    func reassign(from tabID: UUID, to newTabID: UUID) {
        reassigned.append(Moved(from: tabID, to: newTabID))
    }
}

@MainActor
private final class SpaceRunner: AgentRunner {
    let name = "Space runner"
    var waitsForRelease = false
    private(set) var started = 0
    private(set) var transferred: [SpaceLog.Moved] = []
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    func prepare() {}
    func discardSession(forTab tabID: UUID) {}

    func discardAllSessions() {}

    func transferSession(from tabID: UUID, to newTabID: UUID) {
        transferred.append(SpaceLog.Moved(from: tabID, to: newTabID))
    }

    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {
        started += 1
        reply.beginStream()
        reply.update(text: "read both")
        if waitsForRelease {
            await withCheckedContinuation { continuations[task.id] = $0 }
        }
        reply.endStream(retainFor: 60)
    }

    func release(_ taskID: UUID) {
        continuations.removeValue(forKey: taskID)?.resume()
    }
}

@MainActor
private final class SilentSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?

    func speak(_ text: String) {}
    func stopSpeaking() {}
}
