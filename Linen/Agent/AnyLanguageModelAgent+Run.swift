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
        reply.beginStream()
        reply.setActivity(String(localized: "Thinking…"))
        let started = ContinuousClock.now
        let state = RunState(agent: self, utterance: utterance, task: task, reply: reply)
        toolkit.taskLedger = task.isContinuation ? (state.checkpoint.taskLedger ?? .init()) : .init()
        if task.isContinuation, !toolkit.taskLedger.outcomes.isEmpty || toolkit.taskLedger.actionRevision > 0 {
            toolkit.taskLedger.actionRevision += 1
        }
        func event(_ kind: String, _ values: [String: String] = [:]) {
            recordEvent(kind, values, diagnostics: &state.diagnostics, task: task)
        }
        func save() {
            state.checkpoint.taskLedger = toolkit.taskLedger
            let completion = toolkit.taskLedger.completion
            state.checkpoint.completion = state.stop != nil && completion == .answered ? .unverified : completion
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
                tabID: task.spaceID,
                tokens: (state.checkpoint.openAI?.contextTokens ?? Self.estimatedTokens(in: state.checkpoint.transcript)) + budget.toolSchemaTokens
            )
            if !discardedTabIDs.contains(task.spaceID) {
                sessions[task.spaceID] = makeSession(transcript: state.checkpoint.transcript)
            }
        }

        func publishProgress(_ raw: String) {
            let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
            guard !Task.isCancelled, !text.isEmpty else { return }
            log.updateLiveProgress(nil, taskID: task.id)
            if log.latestTrace(forTab: task.spaceID)?.response == text {
                state.reply.update(text: "")
                log.updateResponse("", taskID: task.id, closingSteps: false)
            }
            guard state.checkpoint.progressUpdates?.last?.text != text else { return }
            state.checkpoint.progressUpdates?.append(AgentProgressUpdate(
                text: text, afterStepCount: log.latestTrace(forTab: task.spaceID)?.steps.count ?? 0
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
            } else {
                state.stop = Self.isContextWindowError(error) || error is AgentCompactionFailure ? .contextLimit : .providerError
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
            let ledgerCharacters = toolkit.taskLedger.context.count
            if isOverBudget(state.session, nativeState: state.nativeState, promptCharacters: state.prompt.count + ledgerCharacters + state.images.count * 6_400 + resumeCharacters) {
                callbacks.event("context_compaction", ["reason": "input_budget"])
                try await compact(state, pendingPromptTokens: max(1, (state.prompt.count + ledgerCharacters + resumeCharacters) / 4) + state.images.count * 1_600,
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
                if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if state.policy.requiresOutcomeVerification {
                        switch toolkit.taskLedger.completion {
                        case .unverified:
                            state.verificationRounds += 1
                            if state.verificationRounds < 2 {
                                state.prompt = """
                                    The requested outcomes are not verified. Record any missing outcomes, inspect the result and use verifyTaskOutcome \
                                    for each one. Do not repeat an uncertain submission. If blocked, use blockTaskOutcome.
                                    """
                                continue
                            }
                            state.finalText = ""
                            state.stop = .verificationRequired
                            return
                        case .blocked:
                            state.finalText = answer
                            state.stop = .blocked
                            return
                        case .answered, .verified:
                            break
                        }
                    }
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
            state.progressOnlyRounds = calls.allSatisfy { $0.toolName == UpdateProgressTool.toolName }
                ? state.progressOnlyRounds + 1 : 0
            if state.progressOnlyRounds > 3 {
                state.stop = .noProgress
                break
            }
            try await executeProposals(state, calls: calls, callbacks: callbacks)
        }
    }

    private func generate(_ state: RunState, callbacks: RunCallbacks) async throws -> String? {
        state.observer.calls = []
        state.session.toolExecutionDelegate = state.observer
        let transcriptBeforeRequest = state.session.transcript
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
        var session = state.session
        var nativeState = state.nativeState
        defer {
            state.session = session
            state.nativeState = nativeState
        }
        return try await respond(
            with: &session, nativeState: &nativeState, to: state.prompt + toolkit.taskLedger.context, images: state.images, attachmentInput: state.attachmentInput,
            options: state.barrenTurns > 0 ? answerOptions : options,
            onText: { [log, toolkit] text in
                guard !Task.isCancelled else { return }
                guard !state.policy.requiresOutcomeVerification || toolkit.taskLedger.completion != .unverified else { return }
                state.reply.update(text: text)
                log.updateResponse(text, taskID: state.task.id, closingSteps: false)
            }, onProgress: { [log] text in
                guard !Task.isCancelled else { return }
                state.reply.update(text: text)
                log.updateLiveProgress(text, taskID: state.task.id)
            }, event: event
        )
    }

    private func executeProposals(_ state: RunState, calls: [Transcript.ToolCall], callbacks: RunCallbacks) async throws {
        var needsRecovery = false
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
            if Task.isCancelled || state.stop != nil || needsRecovery {
                break
            }
            if call.toolName == UpdateProgressTool.toolName {
                let arguments = try? UpdateProgressTool.Arguments(call.arguments)
                if let arguments {
                    callbacks.publishProgress(arguments.message)
                }
                entries.append(.toolOutput(.init(
                    id: call.id, toolName: call.toolName,
                    segments: [.text(.init(content: arguments == nil
                        ? "Provide a message containing a short progress update."
                        : "Progress update delivered. Continue with the task.")), ]
                )))
                state.session = makeSession(transcript: Transcript(entries: entries))
                callbacks.save()
                continue
            }
            callbacks.event("tool_proposed", ["name": call.toolName])
            if AgentTaskLedger.mutations.contains(call.toolName) {
                toolkit.taskLedger.beginAction(call.toolName)
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
            state.stop = progress.stop ?? state.stop
        }
        state.session = makeSession(transcript: settledTranscript(state.session.transcript))
        state.prompt = needsRecovery ? Self.recoveryPrompt : Self.continuationPrompt
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
        var progressOnlyRounds = 0
        var overflowRecovered = false
        var finalText: String?
        var submittedUtterance = false
        var originalPrompt: String
        var originalImages: [Transcript.ImageSegment]
        var attachmentInput: OpenAIAttachmentInput?
        var responsePrefix = 0
        var verificationRounds = 0

        init(agent: AnyLanguageModelAgent, utterance: String, task: AgentTaskContext, reply: AgentReplyModel) {
            self.task = task
            self.utterance = utterance
            self.reply = reply
            diagnostics = AgentRunDiagnostics(model: agent.modelID, reasoningEffort: agent.reasoningEffort)
            checkpoint = agent.log.checkpoint(forTab: task.spaceID) ?? AgentCheckpoint()
            nativeState = agent.openAI?.restoring(checkpoint.openAI)
            nativeState?.presentation = .init()
            checkpoint.progressUpdates = []
            session = agent.session(for: task.spaceID)
            policy = agent.executionPolicy ?? .current
            monitor = AgentProgressMonitor(policy: policy)
            prompt = task.isContinuation ? AnyLanguageModelAgent.continuationPrompt : AssistantAttachment.prompt(
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
