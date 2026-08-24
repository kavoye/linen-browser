// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
protocol AgentTurnBrowsing: AnyObject {
    func ensureAgentTabID() -> UUID
    func agentSpaceID(forTab tabID: UUID) -> UUID
    func agentContextSummary(mentionedTabIDs: [UUID]) -> String?
    func setAgentWorking(_ isWorking: Bool, inSpace spaceID: UUID)
}

extension BrowserModel: AgentTurnBrowsing {
    func ensureAgentTabID() -> UUID {
        ensureActiveTab().id
    }

    func agentSpaceID(forTab tabID: UUID) -> UUID {
        spaceID(of: tabID)
    }

    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        contextSummary(mentionedTabIDs: mentionedTabIDs)
    }

    func setAgentWorking(_ isWorking: Bool, inSpace spaceID: UUID) {
        for tab in spaceTabs(spaceID) {
            tab.setAgentWorking(isWorking)
        }
    }
}

@MainActor
protocol AgentTurnLogging: AnyObject {
    func beginTask(_ prompt: String, tabID: UUID) -> UUID
    func completeTask(_ taskID: UUID, response: String)
    func cancelTask(_ taskID: UUID)
    func removeTab(_ tabID: UUID)
    func reassign(from tabID: UUID, to newTabID: UUID)
}

extension ConversationLog: AgentTurnLogging {}

@MainActor
@Observable
final class AgentTurnModel {
    private(set) var reply: AgentReplyModel

    private(set) var runnerName = "none"
    private(set) var activeTask: AgentTaskContext?

    @ObservationIgnored private let browser: any AgentTurnBrowsing
    @ObservationIgnored private let log: any AgentTurnLogging
    @ObservationIgnored private let speech: any SpeechOutput
    @ObservationIgnored private var runner: (any AgentRunner)?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSpaceMoves: [(from: UUID, to: UUID)] = []
    @ObservationIgnored var onTurnFinished: (() -> Void)?

    init(
        browser: any AgentTurnBrowsing,
        log: any AgentTurnLogging,
        speech: any SpeechOutput,
        reply: AgentReplyModel = AgentReplyModel()
    ) {
        self.browser = browser
        self.log = log
        self.speech = speech
        self.reply = reply
    }

    var isRunning: Bool {
        activeTask != nil
    }
    var activeTabID: UUID? {
        activeTask?.tabID
    }
    var activeSpaceID: UUID? {
        activeTask?.spaceID
    }

    func use(_ runner: (any AgentRunner)?) {
        self.runner = runner
        runnerName = runner?.name ?? "none"
    }

    @discardableResult
    func run(utterance: String, mentionedTabIDs: [UUID] = [], trace: LatencyTrace? = nil) -> Bool {
        guard let runner else {
            trace?.end()
            return false
        }

        cancel()
        let tabID = browser.ensureAgentTabID()
        let spaceID = browser.agentSpaceID(forTab: tabID)
        let contextualized: String
        if let context = browser.agentContextSummary(mentionedTabIDs: mentionedTabIDs) {
            contextualized = "\(context)\n\(utterance)"
        } else {
            contextualized = utterance
        }
        let task = AgentTaskContext(
            id: log.beginTask(utterance, tabID: spaceID),
            tabID: tabID,
            spaceID: spaceID,
            mentionedTabIDs: mentionedTabIDs
        )
        browser.setAgentWorking(true, inSpace: spaceID)
        activeTask = task
        reply.bind(toSpace: spaceID)

        let reply = reply
        let speech = speech
        runTask = Task { [weak self] in
            await runner.run(
                utterance: contextualized,
                task: task,
                into: reply,
                speech: speech
            )
            trace?.mark("turnComplete")
            trace?.end()

            guard let self, activeTask?.id == task.id else { return }
            log.completeTask(task.id, response: reply.text ?? "")
            browser.setAgentWorking(false, inSpace: task.spaceID)
            activeTask = nil
            runTask = nil
            applyPendingSpaceMoves()
            onTurnFinished?()
        }
        return true
    }

    func cancel() {
        let hadActiveTurn = activeTask != nil || runTask != nil
        runTask?.cancel()
        runTask = nil
        if let activeTask {
            browser.setAgentWorking(false, inSpace: activeTask.spaceID)
            log.cancelTask(activeTask.id)
            self.activeTask = nil
        }
        reply.clear()
        if hadActiveTurn {
            reply = AgentReplyModel()
        }
        applyPendingSpaceMoves()
    }

    func reassignSpace(from spaceID: UUID, to newSpaceID: UUID) {
        guard spaceID != newSpaceID else { return }
        guard activeTask?.spaceID != spaceID else {
            pendingSpaceMoves.append((from: spaceID, to: newSpaceID))
            return
        }
        log.reassign(from: spaceID, to: newSpaceID)
        runner?.transferSession(from: spaceID, to: newSpaceID)
        if reply.spaceID == spaceID {
            reply.bind(toSpace: newSpaceID)
        }
    }

    private func applyPendingSpaceMoves() {
        let moves = pendingSpaceMoves
        pendingSpaceMoves = []
        for move in moves {
            reassignSpace(from: move.from, to: move.to)
        }
    }

    func forgetEveryConversation() {
        runner?.discardAllSessions()
    }

    @discardableResult
    func closeTab(_ tabID: UUID) -> Bool {
        let endedActiveTurn = activeTask?.tabID == tabID || activeTask?.spaceID == tabID
        if endedActiveTurn {
            cancel()
        }
        runner?.discardSession(forTab: tabID)
        log.removeTab(tabID)
        return endedActiveTurn
    }
}
