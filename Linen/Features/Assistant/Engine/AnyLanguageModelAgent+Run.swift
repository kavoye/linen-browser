// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

extension AnyLanguageModelAgent {
    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {
        toolkit.outputBudget = budget.toolOutput
        toolkit.beginTask(task)
        if !task.isContinuation {
            toolkit.beginRequest(utterance)
        } else if let checkpoint = log.checkpoint(forTab: task.anchorID), let request = checkpoint.request {
            toolkit.resumeRequest(request, answers: checkpoint.userAnswers)
        }
        reply.beginStream()
        reply.setActivity(String(localized: "Thinking…"))
        let started = ContinuousClock.now
        let state = RunState(agent: self, utterance: utterance, task: task, reply: reply)
        func event(_ kind: String, _ values: [String: String] = [:]) {
            recordEvent(kind, values, diagnostics: &state.diagnostics, task: task)
        }
        func save() {
            state.checkpoint.memoryUpdates = toolkit.memoryUpdates.isEmpty ? nil : toolkit.memoryUpdates
            var history = Array(state.session.transcript)
            if !state.submittedUtterance {
                history.append(.prompt(.init(segments: [.text(.init(content: state.originalPrompt))] + state.originalImages.map { .image($0) })))
            }
            state.checkpoint.transcript = settledTranscript(Transcript(entries: history))
            do {
                state.checkpoint.openAI = try state.nativeState?.synchronizing(state.checkpoint.transcript)
            } catch {
                state.checkpoint.openAI = state.nativeState
                state.stop = .providerError
            }
            log.saveCheckpoint(state.checkpoint, taskID: task.id)
            log.recordContextEstimate(
                tabID: task.anchorID,
                tokens: (state.checkpoint.openAI?.contextTokens ?? Self.estimatedTokens(in: state.checkpoint.transcript)) + toolSchemaTokens(for: state.checkpoint.transcript),
                breakdown: Self.contextBreakdown(in: state.checkpoint.transcript, budget: budget, toolTokens: toolSchemaTokens(for: state.checkpoint.transcript))
            )
            if !discardedTabIDs.contains(task.anchorID) {
                sessions[task.anchorID] = makeSession(transcript: state.checkpoint.transcript)
            }
        }

        func publishProgress(_ raw: String) {
            let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
            guard !Task.isCancelled, !text.isEmpty else { return }
            if log.latestTrace(forTab: task.anchorID)?.response == text {
                state.reply.update(text: "")
                log.updateResponse("", taskID: task.id, closingSteps: false)
            }
            guard state.checkpoint.progressUpdates?.last?.text != text else { return }
            state.checkpoint.progressUpdates?.append(AgentProgressUpdate(
                text: text, afterStepCount: log.latestTrace(forTab: task.anchorID)?.steps.count ?? 0
            ))
            event("progress_update", ["status": "completed"])
            save()
        }

        let callbacks = RunCallbacks(save: save, publishProgress: publishProgress, event: event)
        if !acceptsImages {
            log.setAttachments(task.attachments, textOnly: true, taskID: task.id)
        }
        save()
        do {
            try AttachmentRequest.validate(
                task.attachments, message: utterance, textOnly: task.attachmentTextOnly || !acceptsImages,
                windowTokens: budget.windowTokens
            )
            if openAI != nil, !task.isContinuation {
                state.attachmentInput = try OpenAIAttachmentInput.make(prompt: utterance, attachments: task.attachments,
                    textOnly: task.attachmentTextOnly || !acceptsImages)
            }
            try await runLoop(state, callbacks: callbacks)
            if Task.isCancelled {
                state.stop = .interrupted
            }
        } catch is CancellationError {
            state.stop = .interrupted
        } catch {
            state.finalText = (error as? AttachmentFailure)?.errorDescription
                ?? (error as? OpenAIMCPFailure)?.errorDescription ?? state.finalText
            if error is AgentRequestLimitReached {
                state.stop = .requestLimit
            } else if (error as? OpenAIFailure)?.isRateLimited == true {
                state.stop = .rateLimited
            } else {
                state.stop = Self.isContextWindowError(error) || error is AgentCompactionFailure ? .contextLimit : .providerError
            }
            if state.stop == .providerError || state.stop == .rateLimited {
                let failure = error as? OpenAIFailure
                event("provider_failure", [
                    "failure_kind": failure?.kind.rawValue ?? (error is URLError ? "network" : "other"),
                    "http_status": failure?.status.map(String.init) ?? "",
                    "api_code": failure?.code ?? "",
                ])
            }
            if case AgentFailure.emptyResponse = error {
                state.finalText = AgentFailure.emptyResponse.errorDescription
            }
            Pipeline.log.error("Assistant request stopped; see mechanical diagnostics")
        }

        save()
        _ = await finishReply(
            stop: state.stop, text: state.finalText, session: state.session, nativeState: state.nativeState, task: task, reply: reply, speech: speech, event: event
        )
        state.diagnostics.elapsedMilliseconds = Self.milliseconds(since: started)
        log.setDiagnostics(state.diagnostics, taskID: task.id)
        if !Task.isCancelled, !task.isContinuation || toolkit.askedUser {
            await toolkit.writeMemory(using: memoryModel ?? model)
            if !toolkit.memoryUpdates.isEmpty {
                state.checkpoint.memoryUpdates = toolkit.memoryUpdates
                log.saveCheckpoint(state.checkpoint, taskID: task.id)
            }
        }
        log.saveNow()
        toolkit.finishTask(task)
        reply.setActivity(nil)
        reply.endStream()
    }

    private func runLoop(_ state: RunState, callbacks: RunCallbacks) async throws {
        while !Task.isCancelled && state.stop == nil {
            if let limit = state.policy.maxModelRequests, state.diagnostics.modelRequests >= limit {
                state.stop = .requestLimit
                break
            }
            let resumeCharacters = state.task.isContinuation ? AgentCheckpoint.resumePrompt.count + state.utterance.count : 0
            if isOverBudget(state.session, nativeState: state.nativeState, promptCharacters: state.prompt.count + state.images.count * 6_400 + resumeCharacters) {
                callbacks.event("context_compaction", ["reason": "input_budget"])
                try await compact(state, pendingPromptTokens: max(1, (state.prompt.count + resumeCharacters) / 4) + state.images.count * 1_600,
                                  event: callbacks.event)
                callbacks.save()
            }
            if let limit = state.policy.maxModelRequests, state.diagnostics.modelRequests >= limit {
                state.stop = .requestLimit
                break
            }
            if state.task.isContinuation {
                state.session = sessionForContinuation(state.session, pageContext: state.utterance)
            }
            guard let answer = try await generate(state, callbacks: callbacks) else { continue }
            state.overflowRecovered = false
            state.images = []
            state.attachmentInput = nil
            state.session = normalizedSession(state.session, expectedPrefixCount: state.responsePrefix)
            state.session = sessionRemovingEmptyResponses(from: state.session)
            let calls = state.observer.calls
            if calls.isEmpty {
                if toolkit.checkedAnswers < 2, let gap = toolkit.requestConstraints.uncoveredAlternative(in: answer) {
                    toolkit.checkedAnswers += 1
                    let finding = Self.earlierFinding(about: gap.missing, not: gap.covered, in: state.session.transcript)
                    state.prompt = toolkit.requestConstraints.incompleteAnswer(answer, earlier: finding) ?? Self.stepPrompt
                    continue
                }
                if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !answer.contains("<page-content") {
                    state.finalText = answer
                    break
                }
                state.barrenTurns += 1
                guard state.barrenTurns < 2 else { throw AgentFailure.emptyResponse }
                state.prompt = Self.answerPrompt
                continue
            }
            state.barrenTurns = 0
            if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                callbacks.publishProgress(answer)
            }
            try await executeProposals(state, calls: calls, callbacks: callbacks)
        }
    }

    private func generate(_ state: RunState, callbacks: RunCallbacks) async throws -> String? {
        state.observer.calls = []
        state.session.toolExecutionDelegate = state.observer
        let transcriptBeforeRequest = state.session.transcript
        let nativeStateBeforeRequest = state.nativeState
        let wasSubmitted = state.submittedUtterance
        state.responsePrefix = state.session.transcript.count + 1
        callbacks.event("generation", [:])
        let answer: String
        state.submittedUtterance = true
        do {
            if let nativeState = state.nativeState {
                state.nativeState = try nativeState.synchronizing(state.session.transcript)
            }
            let freshApprovals = state.nativeState?.unsubmittedMCPApprovals ?? []
            if !freshApprovals.isEmpty {
                state.nativeState?.recordMCPApprovalAttempts(freshApprovals)
                callbacks.save()
                try log.persistCheckpoint(taskID: state.task.id)
            }
            answer = try await OpenAIMCPExecutionScope.$freshApprovals.withValue(freshApprovals) {
                try await AgentToolProposalScope.$current.withValue(state.observer) {
                    try await respond(state, event: callbacks.event)
                }
            }
        } catch where !state.observer.calls.isEmpty {
            answer = ""
        } catch {
            let remoteActions = openAI.map { !$0.settings.mcpServers.isEmpty || !$0.settings.hostedTools.isEmpty } ?? false
            if !Task.isCancelled, let delay = AgentProviderRetry.delay(for: error, attempt: state.providerRetries, remoteActionsEnabled: remoteActions) {
                state.session = makeSession(transcript: transcriptBeforeRequest)
                state.nativeState = nativeStateBeforeRequest
                state.submittedUtterance = wasSubmitted
                if let limit = state.policy.maxModelRequests, state.diagnostics.modelRequests >= limit {
                    state.stop = .requestLimit
                    return nil
                }
                state.providerRetries += 1
                let retryMessage = (error as? OpenAIFailure)?.isRateLimited == true
                    ? String(localized: "The model provider’s rate limit was reached. Waiting before retrying.")
                    : String(localized: "The model request failed temporarily. Retrying without repeating browser actions.")
                callbacks.publishProgress(retryMessage)
                try await retrySleep(delay)
                return nil
            }
            if let fallback = try imageFallback(
                for: error, task: state.task, utterance: state.utterance,
                transcript: transcriptBeforeRequest, prompt: state.prompt, images: state.images
            ) {
                state.session = fallback.session
                state.prompt = fallback.prompt
                state.images = []
                state.attachmentInput = nil
                state.originalPrompt = fallback.originalPrompt
                state.originalImages = []
                state.submittedUtterance = wasSubmitted
                callbacks.event("attachment_text_fallback", [:])
                return nil
            }
            guard Self.isContextWindowError(error), !state.overflowRecovered else { throw error }
            state.overflowRecovered = true
            callbacks.event("overflow_recovery", [:])
            try await compact(state, event: callbacks.event)
            callbacks.save()
            state.prompt = Self.continuationPrompt
            state.images = []
            state.attachmentInput = nil
            return nil
        }
        state.providerRetries = 0
        return answer
    }

    private func compact(_ state: RunState, pendingPromptTokens: Int = 0, event: (String, [String: String]) -> Void) async throws {
        var checkpoint = state.checkpoint
        var nativeState = state.nativeState
        defer {
            state.checkpoint = checkpoint
            state.nativeState = nativeState
        }
        state.session = try await compact(
            state.session, checkpoint: &checkpoint, nativeState: &nativeState, reply: state.reply,
            pendingPromptTokens: pendingPromptTokens, beforeRequest: { try state.checkCompactionBudget() }, event: event
        )
    }

    private func respond(_ state: RunState, event: (String, [String: String]) -> Void) async throws -> String {
        let withoutTools = state.answerOnly
        var session = withoutTools ? makeSession(transcript: state.session.transcript, withoutTools: true) : state.session
        state.answerOnly = false
        var nativeState = state.nativeState
        defer {
            state.session = session
            state.nativeState = nativeState
        }
        return try await respond(
            with: &session, nativeState: &nativeState, to: state.prompt, images: state.images, attachmentInput: state.attachmentInput,
            options: state.barrenTurns > 0 ? answerOptions : options, withoutTools: withoutTools,
            onText: { [log] text in
                guard !Task.isCancelled else { return }
                state.reply.update(text: text)
                log.updateResponse(text, taskID: state.task.id, closingSteps: false)
            }, event: event
        )
    }

    private func executeProposals(_ state: RunState, calls: [Transcript.ToolCall], callbacks: RunCallbacks) async throws {
        var needsRecovery = false
        var needsAnswer = false
        var entries = Array(state.session.transcript)
        let existing = Set(entries.flatMap { entry -> [String] in
            if case .toolCalls(let calls) = entry {
                return calls.map(\.id)
            }
            return []
        })
        let missing = calls.filter { !existing.contains($0.id) }
        if !missing.isEmpty {
            entries.append(.toolCalls(.init(missing)))
        }
        state.session = makeSession(transcript: Transcript(entries: entries))
        callbacks.save()
        for call in calls {
            if Task.isCancelled || state.stop != nil || needsRecovery || needsAnswer {
                break
            }
            callbacks.event("tool_proposed", ["name": call.toolName])
            if AgentToolCatalog.actionToolIDs.contains(call.toolName) {
                callbacks.save()
                try log.persistCheckpoint(taskID: state.task.id)
            }
            let (output, failed) = await execute(call: call, reply: state.reply, event: callbacks.event)
            entries.append(.toolOutput(output))
            state.session = makeSession(transcript: Transcript(entries: entries))
            let text = Self.text(in: output.segments)
            if call.toolName == "askUser", !failed, !text.isEmpty {
                state.checkpoint.userAnswers.append(text)
            }
            callbacks.save()
            let progress = inspectProgress(state.monitor.observe(
                name: call.toolName, arguments: call.arguments.jsonString, output: text, failed: failed,
                images: output.segments.compactMap { segment in
                    guard case .image(let image) = segment, case .data(let data, _) = image.source else { return nil }
                    return data
                }
            ), event: callbacks.event)
            needsRecovery = progress.recovery
            needsAnswer = progress.answer || toolkit.refusedActions >= 2
            state.stop = progress.stop ?? state.stop
        }
        let onlyRead = calls.allSatisfy { AgentProgressMonitor.readOnlyTools.contains($0.toolName) }
        toolkit.withheldTools = withheldTools(afterRepeatedRead: toolkit.repeatedRead && onlyRead)
        toolkit.repeatedRead = false
        state.session = makeSession(transcript: settledTranscript(state.session.transcript))
        let readingInCircles = needsRecovery && onlyRead
        state.prompt = readingInCircles || needsAnswer ? readStreakPrompt(for: state.session.transcript)
            : needsRecovery ? Self.recoveryPrompt : Self.stepPrompt
        state.answerOnly = needsAnswer
        callbacks.save()
    }

    private final class RunState {
        let task: AgentTaskContext
        let utterance: String
        let reply: AgentReplyModel
        var diagnostics: AgentRunDiagnostics
        var checkpoint: AgentCheckpoint
        var nativeState: OpenAIConversationState?
        var session: LanguageModelSession
        var stop: AgentStopReason?
        let policy: AgentExecutionPolicy
        var monitor: AgentProgressMonitor
        let observer = AgentToolProposalObserver()
        var prompt: String
        var images: [Transcript.ImageSegment]
        var barrenTurns = 0
        var overflowRecovered = false
        var finalText: String?
        var submittedUtterance = false
        var originalPrompt: String
        var originalImages: [Transcript.ImageSegment]
        var attachmentInput: OpenAIAttachmentInput?
        var responsePrefix = 0
        var providerRetries = 0
        var answerOnly = false

        init(agent: AnyLanguageModelAgent, utterance: String, task: AgentTaskContext, reply: AgentReplyModel) {
            self.task = task
            self.utterance = utterance
            self.reply = reply
            diagnostics = AgentRunDiagnostics(model: agent.modelID, reasoningEffort: agent.reasoningEffort)
            checkpoint = agent.log.checkpoint(forTab: task.anchorID) ?? AgentCheckpoint()
            nativeState = agent.openAI?.restoring(checkpoint.openAI)
            nativeState?.presentation = .init()
            checkpoint.progressUpdates = []
            if !task.isContinuation {
                checkpoint.request = utterance
            }
            session = agent.session(for: task.anchorID)
            let policy = agent.executionPolicy ?? .current
            self.policy = policy
            monitor = AgentProgressMonitor(policy: policy)
            prompt = task.isContinuation ? AnyLanguageModelAgent.continuationPrompt : agent.toolkit.rememberedContext(for: utterance) + AssistantAttachment.prompt(
                utterance, attachments: task.attachments, textOnly: task.attachmentTextOnly || !agent.acceptsImages
            )
            images = AttachmentRequest.images(task.attachments, textOnly: task.attachmentTextOnly || !agent.acceptsImages)
            originalPrompt = prompt
            originalImages = images
        }

        func checkCompactionBudget() throws {
            if let limit = policy.maxModelRequests, diagnostics.modelRequests >= limit {
                throw AgentRequestLimitReached()
            }
        }
    }

    private struct RunCallbacks {
        let save: () -> Void
        let publishProgress: (String) -> Void
        let event: (String, [String: String]) -> Void
    }
}
