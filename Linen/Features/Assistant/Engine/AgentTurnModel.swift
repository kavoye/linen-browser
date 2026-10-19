// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
protocol AgentTurnBrowsing: AnyObject {
    func ensureAgentTabID() -> UUID
    func agentAnchorID(forTab tabID: UUID) -> UUID
    func agentContextSummary(mentionedTabIDs: [UUID]) -> String?
    func setAgentWorking(_ isWorking: Bool, inAnchor anchorID: UUID)
}

extension BrowserModel: AgentTurnBrowsing {
    func ensureAgentTabID() -> UUID {
        ensureActiveTab().id
    }

    func agentAnchorID(forTab tabID: UUID) -> UUID {
        anchorID(of: tabID)
    }

    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        contextSummary(mentionedTabIDs: mentionedTabIDs)
    }

    func setAgentWorking(_ isWorking: Bool, inAnchor anchorID: UUID) {
        for tab in anchorTabs(anchorID) {
            tab.setAgentWorking(isWorking)
        }
    }
}

@MainActor
protocol AgentTurnLogging: AnyObject {
    func beginTask(_ prompt: String, tabID: UUID) -> UUID
    func setAttachments(_ attachments: [AssistantAttachment], textOnly: Bool, taskID: UUID)
    func completeTask(_ taskID: UUID, response: String)
    func cancelTask(_ taskID: UUID)
    func removeTab(_ tabID: UUID)
    func reassign(from tabID: UUID, to newTabID: UUID)
    func clearContext(forTab tabID: UUID)
    func clearConversation(forTab tabID: UUID)
}

extension AgentTurnLogging {
    func setAttachments(_ attachments: [AssistantAttachment], textOnly: Bool, taskID: UUID) {}
    func clearContext(forTab tabID: UUID) {}
    func clearConversation(forTab tabID: UUID) {}
}

extension ConversationLog: AgentTurnLogging {}

@MainActor
@Observable
final class AgentTurnModel {
    private(set) var reply: AgentReplyModel

    private(set) var runnerName = "none"
    private(set) var activeTask: AgentTaskContext?
    private(set) var supportsCompaction = false
    private(set) var compactingAnchorID: UUID?
    private(set) var compactionMessage: LocalizedStringResource?
    private(set) var compactionMessageAnchorID: UUID?

    @ObservationIgnored private let browser: any AgentTurnBrowsing
    @ObservationIgnored private var log: any AgentTurnLogging
    @ObservationIgnored private let speech: any SpeechOutput
    @ObservationIgnored private var modelSettings: LLMSettings
    @ObservationIgnored private var actionPolicy: AgentActionPolicy
    @ObservationIgnored private var runner: (any AgentRunner)?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var completion: ((Result<AgentTurnResult, any Error>) -> Void)?
    @ObservationIgnored private var compactionTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAnchorMoves: [(from: UUID, to: UUID)] = []
    @ObservationIgnored var onTurnFinished: (() -> Void)?

    var onCancel: (() -> Void)?

    init(
        browser: any AgentTurnBrowsing,
        log: any AgentTurnLogging,
        speech: any SpeechOutput,
        modelSettings: LLMSettings = .current,
        actionPolicy: AgentActionPolicy = .shared,
        reply: AgentReplyModel = AgentReplyModel()
    ) {
        self.browser = browser
        self.log = log
        self.speech = speech
        self.modelSettings = modelSettings
        self.actionPolicy = actionPolicy
        self.reply = reply
    }

    var isRunning: Bool {
        activeTask != nil
    }
    var activeTabID: UUID? {
        activeTask?.tabID
    }

    func adopt(log: any AgentTurnLogging) {
        guard self.log !== log else { return }
        cancel()
        forgetEveryConversation()
        self.log = log
        reply = AgentReplyModel()
    }

    func adopt(context: BrowserProfileContext) {
        adopt(log: context.conversationLog)
        modelSettings = context.modelSettings
        actionPolicy = context.actionPolicy
    }

    /// Stop this window's work before a page changes owner, keeping its saved conversation.
    func detachTab(_ tabID: UUID, inAnchor anchorID: UUID) {
        cancel()
        runner?.discardSession(forTab: tabID)
        if anchorID != tabID {
            runner?.discardSession(forTab: anchorID)
        }
        if reply.anchorID == tabID || reply.anchorID == anchorID {
            reply = AgentReplyModel()
        }
    }

    func use(_ runner: (any AgentRunner)?) {
        cancelCompaction()
        self.runner = runner
        runnerName = runner?.name ?? "none"
        supportsCompaction = runner?.supportsCompaction == true
        runner?.refreshContextEstimates()
    }

    func compactContext(inAnchor anchorID: UUID) {
        guard !isRunning, compactingAnchorID == nil, let runner, runner.supportsCompaction else { return }
        compactingAnchorID = anchorID
        compactionMessage = nil
        compactionMessageAnchorID = anchorID
        let modelSettings = modelSettings
        compactionTask = Task { [weak self] in
            let message: LocalizedStringResource
            do {
                let changed = try await LLMSettings.$scoped.withValue(modelSettings) {
                    try await runner.compactContext(forTab: anchorID)
                }
                message = changed ? "Context compacted" : "No context to compact"
            } catch {
                message = "Couldn’t compact. Context unchanged."
            }
            guard !Task.isCancelled, let self else { return }
            compactionMessage = message
            compactingAnchorID = nil
            compactionTask = nil
        }
    }

    func clearContext(inAnchor anchorID: UUID, conversation: Bool) {
        guard !isRunning, compactingAnchorID == nil else { return }
        runner?.resetSession(forTab: anchorID)
        if conversation {
            log.clearConversation(forTab: anchorID)
        } else {
            log.clearContext(forTab: anchorID)
        }
        if reply.anchorID == anchorID {
            reply = AgentReplyModel()
        }
        compactionMessageAnchorID = anchorID
        compactionMessage = "Context cleared"
    }

    private func cancelCompaction() {
        compactionTask?.cancel()
        compactionTask = nil
        compactingAnchorID = nil
        compactionMessage = nil
        compactionMessageAnchorID = nil
    }

    @discardableResult
    func run(
        utterance: String,
        mentionedTabIDs: [UUID] = [],
        attachments: [AssistantAttachment] = [],
        attachmentTextOnly: Bool = false,
        isContinuation: Bool = false,
        trace: LatencyTrace? = nil,
        showsInChrome: Bool = true,
        speechOverride: (any SpeechOutput)? = nil,
        completion: ((Result<AgentTurnResult, any Error>) -> Void)? = nil
    ) -> Bool {
        guard let runner else {
            trace?.end()
            return false
        }

        cancel()
        self.completion = completion
        let tabID = browser.ensureAgentTabID()
        let anchorID = browser.agentAnchorID(forTab: tabID)
        let contextualized: String
        if let context = browser.agentContextSummary(mentionedTabIDs: mentionedTabIDs) {
            contextualized = "\(context)\n\(utterance)"
        } else {
            contextualized = utterance
        }
        let traceID = LLMSettings.$scoped.withValue(modelSettings) {
            log.beginTask(isContinuation ? "" : utterance, tabID: anchorID)
        }
        let task = AgentTaskContext(
            id: traceID,
            tabID: tabID,
            anchorID: anchorID,
            mentionedTabIDs: mentionedTabIDs,
            attachments: attachments,
            attachmentTextOnly: attachmentTextOnly,
            isContinuation: isContinuation
        )
        log.setAttachments(attachments, textOnly: attachmentTextOnly, taskID: task.id)
        browser.setAgentWorking(true, inAnchor: anchorID)
        activeTask = task
        reply.bind(toAnchor: anchorID, showsInChrome: showsInChrome)

        let reply = reply
        let speech = speechOverride ?? speech
        let modelSettings = modelSettings
        let actionPolicy = actionPolicy
        runTask = Task { [weak self] in
            await LLMSettings.$scoped.withValue(modelSettings) {
                await task.driver.scope(policy: actionPolicy) {
                    await runner.run(
                        utterance: contextualized,
                        task: task,
                        into: reply,
                        speech: speech
                    )
                }
            }
            trace?.mark("turnComplete")
            trace?.end()

            guard let self, activeTask?.id == task.id else { return }
            log.completeTask(task.id, response: reply.text ?? "")
            browser.setAgentWorking(false, inAnchor: task.anchorID)
            activeTask = nil
            runTask = nil
            applyPendingAnchorMoves()
            let completed = self.completion
            self.completion = nil
            onTurnFinished?()
            completed?(.success(.init(taskID: task.id, text: reply.text ?? "")))
        }
        return true
    }

    func cancel() {
        cancelCompaction()
        let hadActiveTurn = activeTask != nil || runTask != nil
        onCancel?()
        runTask?.cancel()
        runTask = nil
        if let activeTask {
            browser.setAgentWorking(false, inAnchor: activeTask.anchorID)
            log.cancelTask(activeTask.id)
            self.activeTask = nil
        }
        reply.clear()
        if hadActiveTurn {
            reply = AgentReplyModel()
        }
        let completed = completion
        completion = nil
        applyPendingAnchorMoves()
        completed?(.failure(CancellationError()))
    }

    func reassignAnchor(from anchorID: UUID, to newAnchorID: UUID) {
        guard anchorID != newAnchorID else { return }
        if compactingAnchorID == anchorID {
            cancelCompaction()
        }
        guard activeTask?.anchorID != anchorID else {
            pendingAnchorMoves.append((from: anchorID, to: newAnchorID))
            return
        }
        log.reassign(from: anchorID, to: newAnchorID)
        runner?.transferSession(from: anchorID, to: newAnchorID)
        if reply.anchorID == anchorID {
            reply.bind(toAnchor: newAnchorID, showsInChrome: reply.showsInChrome)
        }
    }

    private func applyPendingAnchorMoves() {
        let moves = pendingAnchorMoves
        pendingAnchorMoves = []
        for move in moves {
            reassignAnchor(from: move.from, to: move.to)
        }
    }

    func forgetEveryConversation() {
        cancelCompaction()
        runner?.discardAllSessions()
    }

    @discardableResult
    func closeTab(_ tabID: UUID, keepingConversation: Bool = false) -> Bool {
        if compactingAnchorID == tabID {
            cancelCompaction()
        }
        let endedActiveTurn = activeTask?.tabID == tabID || activeTask?.anchorID == tabID
        if endedActiveTurn {
            cancel()
        }
        runner?.discardSession(forTab: tabID)
        if !keepingConversation {
            log.removeTab(tabID)
        }
        return endedActiveTurn
    }

    func reopenTab(_ tabID: UUID, as newTabID: UUID) {
        log.reassign(from: tabID, to: newTabID)
    }

    func forgetClosedTab(_ tabID: UUID) {
        log.removeTab(tabID)
    }
}
