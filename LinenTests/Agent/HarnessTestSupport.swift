// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

@testable import Linen

final class HarnessScript: LanguageModel, @unchecked Sendable {
    enum Action {
        case text(String)
        case calls([String])
        case commentary(String, [String])
        case progress(String)
        case failure(any Error)
    }
    private let lock = NSLock()
    private var actions: [Action]
    private var seen: [Transcript] = []
    private var prompts: [String] = []
    var summary = "The earlier fields were completed. Continue with the remaining fields."
    var summaryInputLimit: Int?
    var summaryFailure: (any Error)?

    init(_ actions: [Action]) {
        self.actions = actions
    }

    var transcripts: [Transcript] {
        lock.withLock { seen }
    }

    var requests: [String] {
        lock.withLock { prompts }
    }

    func respond<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let action: Action = lock.withLock {
            seen.append(session.transcript)
            prompts.append(prompt.description)
            if prompt.description.contains("historical checkpoint") || prompt.description.contains("browser task is paused") {
                if let summaryFailure {
                    return .failure(summaryFailure)
                }
                if let summaryInputLimit, prompt.description.utf8.count > summaryInputLimit {
                    return .failure(LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "fixture")))
                }
                return .text(summary)
            }
            return actions.isEmpty ? .text("Done.") : actions.removeFirst()
        }
        var entries: [Transcript.Entry] = []
        let text: String
        switch action {
        case .failure(let error):
            throw error
        case .text(let value):
            text = value
        case .calls(let names), .commentary(_, let names):
            let calls = names.map { name in
                Transcript.ToolCall(id: UUID().uuidString, toolName: name,
                                    arguments: GeneratedContent(properties: ["value": GeneratedContent("fixture-value")]))
            }
            entries = [.toolCalls(.init(calls))]
            if case .commentary(let message, _) = action { text = message } else { text = "" }
        case .progress(let message):
            entries = [.toolCalls(.init([Transcript.ToolCall(
                id: UUID().uuidString, toolName: "updateProgress",
                arguments: GeneratedContent(properties: ["message": GeneratedContent(message)])
            ), ])), ]
            text = ""
        }
        for entry in entries {
            if case .toolCalls(let calls) = entry, let delegate = session.toolExecutionDelegate {
                let proposed = Array(calls)
                await delegate.didGenerateToolCalls(proposed, in: session)
                for call in proposed {
                    guard case .stop = await delegate.toolCallDecision(for: call, in: session) else {
                        throw HarnessFixtureFailure()
                    }
                }
            }
        }
        guard let content = text as? Content else { throw HarnessFixtureFailure() }
        return .init(content: content, rawContent: GeneratedContent(text), transcriptEntries: entries[...])
    }

    func streamResponse<Content>(
        within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
        includeSchemaInPrompt: Bool, options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        guard let content = "unexpected streaming" as? Content else {
            fatalError("Fixture supports String output only")
        }
        return .init(content: content, rawContent: GeneratedContent("unexpected streaming"))
    }
}

struct HarnessFixtureFailure: LocalizedError {
    var errorDescription: String? { "private@example.test passport ABC123" }
}

@MainActor
final class HarnessToolState {
    var calls = 0
    var output: (Int) async throws -> String = { "Observed state \($0)" }

    func invoke() async throws -> String {
        calls += 1
        return try await output(calls)
    }
}

nonisolated struct HarnessTool: Tool {
    let name: String
    let description = "Fixture tool"
    let state: HarnessToolState

    @Generable struct Arguments {
        var value: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await state.invoke()
    }
}

@MainActor
final class HarnessSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?
    var spoken: [String] = []
    func speak(_ text: String) {
        spoken.append(text)
    }
    func stopSpeaking() {}
}

@MainActor
struct HarnessFixture {
    let database: AppDatabase
    let log: ConversationLog
    let model: HarnessScript
    let state: HarnessToolState
    let agent: AnyLanguageModelAgent
    let reply = AgentReplyModel()
    let speech = HarnessSpeech()
    let tabID: UUID

    init(
        _ actions: [HarnessScript.Action], policy: AgentExecutionPolicy = .init(requiresOutcomeVerification: false),
        inputTokens: Int = 100_000, database: AppDatabase? = nil, tabID: UUID = UUID(),
        state: HarnessToolState? = nil, contextBudget: ContextBudget? = nil,
        openAI: OpenAIResponsesClient? = nil
    ) {
        let database = database ?? .temporary()
        self.database = database
        self.tabID = tabID
        let log = ConversationLog(database: database)
        self.log = log
        let state = state ?? HarnessToolState()
        self.state = state
        let model = HarnessScript(actions)
        self.model = model
        agent = AnyLanguageModelAgent(
            name: "fixture", modelID: "gpt-5.6-luna", reasoningEffort: "medium",
            executionPolicy: policy,
            toolOverrides: ["readPage", "typeOnPage", "clickAtPoint", "askUser"].map { HarnessTool(name: $0, state: state) },
            openAI: openAI,
            model: model, options: GenerationOptions(),
            budget: contextBudget ?? ContextBudget(
                windowTokens: 128_000, responseTokens: 2_000, inputTokens: inputTokens,
                toolSchemaTokens: 0, instructionTier: .compact, toolTier: .full,
                toolOutput: .standard, retainedExchanges: 12, retainedToolRounds: 1
            ),
            toolkit: AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log),
            log: log
        )
    }

    @discardableResult
    func run(_ prompt: String = "Fill the fixture form", attachments: [AssistantAttachment] = [], isContinuation: Bool = false) async -> UUID {
        let id = log.beginTask(isContinuation ? "" : prompt, tabID: tabID)
        log.setAttachments(attachments, textOnly: false, taskID: id)
        await agent.run(utterance: prompt, task: .init(id: id, tabID: tabID, attachments: attachments, isContinuation: isContinuation), into: reply, speech: speech)
        log.completeTask(id, response: reply.text ?? "")
        log.saveBlocking()
        return id
    }

    static func flattened(_ transcript: Transcript) -> String {
        String(decoding: (try? JSONEncoder().encode(transcript)) ?? Data(), as: UTF8.self)
    }
}
