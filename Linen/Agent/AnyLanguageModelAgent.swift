// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

@MainActor
final class AnyLanguageModelAgent: AgentRunner {
    let name: String

    static var isSystemModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    private static let continuationPrompt = "Continue the task using the tool result."
    private static let answerPrompt = "Answer the user now, in plain words."
    private static let scaffoldingPrompts: Set<String> = [continuationPrompt, answerPrompt]
    private static var giveUpReply: String {
        String(localized: "This task needed more steps than expected. Try asking again.")
    }

    private let model: any LanguageModel
    private let options: GenerationOptions
    private let answerOptions: GenerationOptions
    let budget: ContextBudget
    private let enabledToolIDs: Set<String>?
    private let toolkit: AgentToolkit
    private let log: ConversationLog

    private var sessions: [UUID: LanguageModelSession] = [:]
    private var discardedTabIDs = RecentIDs()
    private var prewarmedSession: LanguageModelSession?

    init(
        name: String,
        model: any LanguageModel,
        options: GenerationOptions,
        answerOptions: GenerationOptions? = nil,
        budget: ContextBudget,
        enabledToolIDs: Set<String>? = nil,
        toolkit: AgentToolkit,
        log: ConversationLog
    ) {
        self.name = name
        self.model = model
        self.options = options
        self.answerOptions = answerOptions ?? options
        self.budget = budget
        self.enabledToolIDs = enabledToolIDs
        self.toolkit = toolkit
        self.log = log
    }

    func prepare() {
        guard prewarmedSession == nil else { return }
        let session = makeSession()
        session.prewarm()
        prewarmedSession = session
    }

    func discardSession(forTab tabID: UUID) {
        discardedTabIDs.insert(tabID)
        sessions.removeValue(forKey: tabID)
    }

    func transferSession(from tabID: UUID, to newTabID: UUID) {
        guard tabID != newTabID,
              sessions[newTabID] == nil,
              !discardedTabIDs.contains(newTabID),
              let session = sessions.removeValue(forKey: tabID)
        else { return }
        sessions[newTabID] = session
    }

    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {
        toolkit.outputBudget = budget.toolOutput
        toolkit.beginTask(task)
        reply.beginStream()
        reply.setActivity(String(localized: "Thinking…"))

        var session = session(for: task.spaceID)
        if session.isResponding {
            session = makeSession()
            sessions[task.spaceID] = session
        }

        var shouldCommitResult = false

        do {
            var completion: Completion
            do {
                completion = try await completeTurn(
                    utterance: utterance,
                    startingWith: session,
                    reply: reply
                )
            } catch {
                guard Self.isContextWindowError(error) else { throw error }
                Pipeline.log.warning("Context window exceeded; retrying on a clean session")
                completion = try await completeTurn(
                    utterance: utterance,
                    startingWith: makeSession(),
                    reply: reply
                )
            }

            session = completion.session
            let final = completion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw AgentFailure.emptyResponse }

            reply.setActivity(nil)
            reply.update(text: final)
            log.updateResponse(final, taskID: task.id)
            speech.speak(AIDisclosure.spokenPrefix() + final)
            shouldCommitResult = true
        } catch is CancellationError {
        } catch {
            Pipeline.log.error("Agent turn failed: \(error.localizedDescription, privacy: .public)")
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn’t reach the model provider. Check its connection and API key in Settings.")
            reply.update(text: message)
            log.failTask(task.id, reason: message)
        }

        if !discardedTabIDs.contains(task.spaceID) {
            let compacted = compactedSession(from: session)
            sessions[task.spaceID] = compacted
            log.recordContextEstimate(
                tabID: task.spaceID,
                tokens: Self.estimatedTokens(in: compacted.transcript)
            )
        }

        toolkit.finishTask(task, commitResult: shouldCommitResult)
        reply.setActivity(nil)
        reply.endStream()
    }

    private struct Completion {
        let text: String
        let session: LanguageModelSession
    }

    private func completeTurn(
        utterance: String,
        startingWith initialSession: LanguageModelSession,
        reply: AgentReplyModel
    ) async throws -> Completion {
        let observer = AgentToolExecutionObserver(reply: reply, maxToolCalls: budget.maxToolCalls)
        var session = initialSession
        session.toolExecutionDelegate = observer
        var prompt = utterance
        var turnOptions = options
        var barrenTurns = 0
        var hasRecoveredFromOverflow = false

        for _ in 0..<budget.maxToolCalls {
            try Task.checkCancellation()
            let callsBeforeResponse = observer.acceptedToolCalls

            session = preparedSession(session, promptCharacters: prompt.count)
            session.toolExecutionDelegate = observer
            var expectedPrefixCount = session.transcript.count + 1

            let response: LanguageModelSession.Response<String>
            do {
                response = try await session.respond(to: prompt, options: turnOptions)
            } catch {
                guard Self.isContextWindowError(error), !hasRecoveredFromOverflow else { throw error }
                hasRecoveredFromOverflow = true
                Pipeline.log.warning("Context window exceeded mid-turn; compacting and retrying")
                session = overflowCompacted(from: session)
                session.toolExecutionDelegate = observer
                expectedPrefixCount = session.transcript.count + 1
                response = try await session.respond(to: prompt, options: turnOptions)
            }

            session = normalizedSession(
                session,
                expectedPrefixCount: expectedPrefixCount
            )
            session.toolExecutionDelegate = observer

            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return Completion(text: text, session: session)
            }
            if observer.stoppedAtLimit {
                return Completion(text: Self.giveUpReply, session: session)
            }

            if observer.acceptedToolCalls > callsBeforeResponse {
                barrenTurns = 0
                turnOptions = options
                prompt = Self.continuationPrompt
            } else {
                barrenTurns += 1
                guard barrenTurns < 2 else { throw AgentFailure.emptyResponse }
                turnOptions = answerOptions
                prompt = Self.answerPrompt
            }

            session = sessionRemovingEmptyResponses(from: session)
            session.toolExecutionDelegate = observer
            reply.setActivity(String(localized: "Thinking…"))
        }

        return Completion(text: Self.giveUpReply, session: session)
    }

    private func preparedSession(
        _ session: LanguageModelSession,
        promptCharacters: Int
    ) -> LanguageModelSession {
        guard isOverBudget(session, promptCharacters: promptCharacters) else { return session }
        let trimmed = trimmedToRetainedRounds(from: session)
        guard isOverBudget(trimmed, promptCharacters: promptCharacters) else { return trimmed }
        return overflowCompacted(from: trimmed)
    }

    private func isOverBudget(
        _ session: LanguageModelSession,
        promptCharacters: Int
    ) -> Bool {
        Self.estimatedTokens(in: session.transcript)
            + max(1, promptCharacters / 4)
            + budget.toolSchemaTokens
            > budget.inputTokens
    }

    private func trimmedToRetainedRounds(
        from session: LanguageModelSession
    ) -> LanguageModelSession {
        let entries = Array(session.transcript)
        guard let promptIndex = Self.lastUtterancePromptIndex(in: entries) else { return session }
        let roundStarts = ((promptIndex + 1)..<entries.count).filter { index in
            if case .toolCalls = entries[index] {
                return true
            }
            return false
        }
        guard roundStarts.count > budget.retainedToolRounds else { return session }
        let keepFrom = roundStarts[roundStarts.count - budget.retainedToolRounds]
        let kept = Array(entries[...promptIndex]) + Array(entries[keepFrom...])
        return makeSession(transcript: Transcript(entries: kept))
    }

    private func overflowCompacted(
        from session: LanguageModelSession
    ) -> LanguageModelSession {
        let entries = Array(session.transcript)
        var kept = entries.filter { entry in
            if case .instructions = entry {
                return true
            }
            return false
        }
        if let promptIndex = Self.lastUtterancePromptIndex(in: entries) {
            kept.append(entries[promptIndex])
            if promptIndex + 1 < entries.count, case .response = entries[promptIndex + 1] {
                kept.append(entries[promptIndex + 1])
            }
            let tail = (promptIndex + 1)..<entries.count
            let lastRoundStart = tail.last { index in
                if case .toolCalls = entries[index] {
                    return true
                }
                return false
            }
            if let lastRoundStart {
                let cap = max(400, budget.toolOutput.pageTextCharacters / 2)
                for entry in entries[lastRoundStart...] {
                    switch entry {
                    case .toolCalls:
                        kept.append(entry)
                    case .toolOutput(let output):
                        kept.append(.toolOutput(Self.truncated(output, to: cap)))
                    default:
                        break
                    }
                }
            }
        }
        guard kept != entries else { return session }
        return makeSession(transcript: Transcript(entries: kept))
    }

    private static func truncated(
        _ output: Transcript.ToolOutput,
        to cap: Int
    ) -> Transcript.ToolOutput {
        Transcript.ToolOutput(
            id: output.id,
            toolName: output.toolName,
            segments: output.segments.map { segment in
                guard case .text(let text) = segment, text.content.count > cap else {
                    return segment
                }
                return .text(.init(content: String(text.content.prefix(cap))))
            }
        )
    }

    private static func lastUtterancePromptIndex(in entries: [Transcript.Entry]) -> Int? {
        entries.lastIndex { entry in
            guard case .prompt(let prompt) = entry else { return false }
            return !scaffoldingPrompts.contains(text(in: prompt.segments))
        }
    }

    private func normalizedSession(
        _ session: LanguageModelSession,
        expectedPrefixCount: Int
    ) -> LanguageModelSession {
        var entries = Array(session.transcript)
        guard expectedPrefixCount > 0,
              entries.count >= expectedPrefixCount * 2,
              Array(entries[0..<expectedPrefixCount])
                == Array(entries[expectedPrefixCount..<(expectedPrefixCount * 2)])
        else { return session }

        entries.removeSubrange(expectedPrefixCount..<(expectedPrefixCount * 2))
        return makeSession(transcript: Transcript(entries: entries))
    }

    private func sessionRemovingEmptyResponses(
        from session: LanguageModelSession
    ) -> LanguageModelSession {
        let entries = Array(session.transcript).filter { entry in
            guard case .response(let response) = entry else { return true }
            return !Self.text(in: response.segments)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        guard entries.count != session.transcript.count else { return session }
        return makeSession(transcript: Transcript(entries: entries))
    }

    private func compactedSession(from session: LanguageModelSession) -> LanguageModelSession {
        var instructions: [Transcript.Entry] = []
        var exchanges: [Transcript.Entry] = []

        for entry in session.transcript {
            switch entry {
            case .instructions:
                instructions.append(entry)
            case .prompt(let prompt):
                if !Self.scaffoldingPrompts.contains(Self.text(in: prompt.segments)) {
                    exchanges.append(entry)
                }
            case .response(let response):
                if !Self.text(in: response.segments)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    exchanges.append(entry)
                }
            case .toolCalls, .toolOutput:
                continue
            }
        }

        if case .prompt = exchanges.last {
            exchanges.removeLast()
        }
        let limit = budget.retainedExchanges * 2
        if exchanges.count > limit {
            exchanges = Array(exchanges.suffix(limit))
        }

        let retained = instructions + exchanges
        guard retained != Array(session.transcript) else { return session }

        let compacted = makeSession(transcript: Transcript(entries: retained))
        compacted.prewarm()
        return compacted
    }

    private func session(for tabID: UUID) -> LanguageModelSession {
        if let session = sessions[tabID] {
            return session
        }

        let exchanges = log.exchanges(forTab: tabID, limit: budget.retainedExchanges)
        let session: LanguageModelSession
        if exchanges.isEmpty {
            session = prewarmedSession ?? makeSession()
            prewarmedSession = nil
        } else {
            let base = makeSession()
            var entries = Array(base.transcript)
            for exchange in exchanges {
                entries.append(.prompt(.init(
                    segments: [.text(.init(content: exchange.prompt))]
                )))
                entries.append(.response(.init(
                    assetIDs: [],
                    segments: [.text(.init(content: exchange.response))]
                )))
            }
            session = makeSession(transcript: Transcript(entries: entries))
            session.prewarm()
        }

        if !discardedTabIDs.contains(tabID) {
            sessions[tabID] = session
        }
        return session
    }

    private func makeSession(transcript: Transcript? = nil) -> LanguageModelSession {
        let tools: [any Tool]
        if let enabledToolIDs {
            tools = makeAgentTools(toolkit: toolkit, enabledIDs: enabledToolIDs)
        } else {
            tools = makeAgentTools(toolkit: toolkit, tier: budget.toolTier)
        }
        if let transcript {
            return LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
        return LanguageModelSession(
            model: model,
            tools: tools,
            instructions: AgentInstructions.text(for: budget.instructionTier)
        )
    }

    private static func text(in segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined()
    }

    private static func estimatedTokens(in transcript: Transcript) -> Int {
        let characters = transcript.reduce(into: 0) { count, entry in
            switch entry {
            case .instructions(let value):
                count += text(in: value.segments).count
            case .prompt(let value):
                count += text(in: value.segments).count
            case .response(let value):
                count += text(in: value.segments).count
            case .toolCalls(let calls):
                count += calls.reduce(0) { partial, call in
                    partial + call.toolName.count + call.arguments.jsonString.count
                }
            case .toolOutput(let value):
                count += text(in: value.segments).count
            }
        }
        return characters == 0 ? 0 : max(1, characters / 4)
    }

    private static func isContextWindowError(_ error: any Error) -> Bool {
        guard let error = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = error {
            return true
        }
        return false
    }
}

@MainActor
private final class AgentToolExecutionObserver: ToolExecutionDelegate {
    private weak var reply: AgentReplyModel?
    private let maxToolCalls: Int

    private(set) var acceptedToolCalls = 0
    private(set) var stoppedAtLimit = false

    init(reply: AgentReplyModel, maxToolCalls: Int) {
        self.reply = reply
        self.maxToolCalls = maxToolCalls
    }

    func didGenerateToolCalls(
        _ toolCalls: [Transcript.ToolCall],
        in session: LanguageModelSession
    ) async {
        if let call = toolCalls.first {
            reply?.setActivity(Self.activityLabel(for: call))
        }
    }

    func toolCallDecision(
        for toolCall: Transcript.ToolCall,
        in session: LanguageModelSession
    ) async -> ToolExecutionDecision {
        guard acceptedToolCalls < maxToolCalls else {
            stoppedAtLimit = true
            return .stop
        }
        acceptedToolCalls += 1
        reply?.setActivity(Self.activityLabel(for: toolCall))
        return .execute
    }

    func didExecuteToolCall(
        _ toolCall: Transcript.ToolCall,
        output: Transcript.ToolOutput,
        in session: LanguageModelSession
    ) async {
        reply?.setActivity(String(localized: "Thinking…"))
    }

    func didFailToolCall(
        _ toolCall: Transcript.ToolCall,
        error: any Error,
        in session: LanguageModelSession
    ) async {
        reply?.setActivity(String(localized: "The browser action failed…"))
    }

    private static func activityLabel(for call: Transcript.ToolCall) -> String {
        let args = arguments(for: call)
        switch call.toolName {
        case "searchWeb":
            let query = text(args, "query")
            let searching: LocalizedStringResource = query.isEmpty
                ? "Searching the web…"
                : "Searching the web for “\(query)”…"
            return String(localized: searching)
        case "navigate":
            let host = URL(string: args["url"] as? String ?? "")?.host()
                ?? String(localized: "the page")
            return String(localized: "Opening \(host)…")
        case "readPage":
            return String(localized: "Reading the page…")
        case "clickOnPage":
            let label = text(args, "label")
            let clicking: LocalizedStringResource = label.isEmpty
                ? "Clicking…"
                : "Clicking “\(label)”…"
            return String(localized: clicking)
        case "typeOnPage":
            let typed = text(args, "text")
            let typing: LocalizedStringResource = typed.isEmpty
                ? "Typing…"
                : "Typing “\(typed)”…"
            return String(localized: typing)
        case "selectOption":
            let option = text(args, "option")
            let choosing: LocalizedStringResource = option.isEmpty
                ? "Choosing an option…"
                : "Choosing “\(option)”…"
            return String(localized: choosing)
        case "scrollPage":
            return String(localized: "Scrolling…")
        case "goBack":
            return String(localized: "Going back…")
        case "playVideo":
            let topic = text(args, "topic")
            let finding: LocalizedStringResource = topic.isEmpty
                ? "Finding a video…"
                : "Finding a video: \(topic)…"
            return String(localized: finding)
        case "closeVideo":
            return String(localized: "Closing the video…")
        case "controlMedia":
            return String(localized: "Adjusting the player…")
        case "newTab":
            return String(localized: "Opening a new tab…")
        case "switchTab":
            return String(localized: "Switching tabs…")
        case "closeTab":
            return String(localized: "Closing the tab…")
        default:
            return String(localized: "Working…")
        }
    }

    private static func text(_ args: [String: Any], _ key: String) -> String {
        (args[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func arguments(for call: Transcript.ToolCall) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(call.arguments),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}

private enum AgentFailure: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        String(localized: "The model returned an empty response. Try again or choose another model.")
    }
}
