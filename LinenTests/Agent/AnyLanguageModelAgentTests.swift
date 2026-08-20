// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

/// The turn loop in `AnyLanguageModelAgent`, driven end to end through a
/// scripted model instead of a provider: continuation after a tool round,
/// recovery from a barren turn, the give-up reply at the tool budget, and
/// the clean-session retry after a context-window overflow. The scripts
/// stand in for real provider behaviour each path was built against.
@MainActor
struct AnyLanguageModelAgentTests {
    private final class ScriptedModel: LanguageModel, @unchecked Sendable {
        enum Turn {
            case text(String)
            case toolCall(named: String)
            case error(any Error)
        }

        private let lock = NSLock()
        private var turns: [Turn]
        private var recorded: [String] = []

        init(turns: [Turn]) {
            self.turns = turns
        }

        var prompts: [String] {
            lock.withLock { recorded }
        }

        private func nextTurn(recording prompt: String) -> Turn {
            lock.withLock {
                recorded.append(prompt)
                return turns.isEmpty ? .text("") : turns.removeFirst()
            }
        }

        func respond<Content>(
            within session: LanguageModelSession,
            to prompt: Prompt,
            generating type: Content.Type,
            includeSchemaInPrompt: Bool,
            options: GenerationOptions
        ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
            switch nextTurn(recording: prompt.description) {
            case .error(let error):
                throw error
            case .text(let text):
                guard let content = text as? Content else {
                    fatalError("the scripted model only generates String")
                }
                return .init(
                    content: content,
                    rawContent: GeneratedContent(text),
                    transcriptEntries: []
                )
            case .toolCall(let name):
                let call = Transcript.ToolCall(
                    id: UUID().uuidString,
                    toolName: name,
                    arguments: GeneratedContent(properties: [:])
                )
                var entries: [Transcript.Entry] = [.toolCalls(.init([call]))]
                if let delegate = session.toolExecutionDelegate {
                    await delegate.didGenerateToolCalls([call], in: session)
                    switch await delegate.toolCallDecision(for: call, in: session) {
                    case .stop:
                        break
                    case .execute, .provideOutput:
                        let output = Transcript.ToolOutput(
                            id: call.id,
                            toolName: name,
                            segments: [.text(.init(content: "ok"))]
                        )
                        await delegate.didExecuteToolCall(call, output: output, in: session)
                        entries.append(.toolOutput(output))
                    }
                }
                guard let content = "" as? Content else {
                    fatalError("the scripted model only generates String")
                }
                return .init(
                    content: content,
                    rawContent: GeneratedContent(""),
                    transcriptEntries: entries[...]
                )
            }
        }

        func streamResponse<Content>(
            within session: LanguageModelSession,
            to prompt: Prompt,
            generating type: Content.Type,
            includeSchemaInPrompt: Bool,
            options: GenerationOptions
        ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
            guard let content = "" as? Content else {
                fatalError("the scripted model only generates String")
            }
            return .init(content: content, rawContent: GeneratedContent(""))
        }
    }

    private final class SilentSpeech: SpeechOutput {
        var isMuted = false
        var onSpeakingChange: ((Bool) -> Void)?
        private(set) var spoken: [String] = []

        func speak(_ text: String) {
            spoken.append(text)
        }

        func stopSpeaking() {}
    }

    private struct Turn {
        let agent: AnyLanguageModelAgent
        let model: ScriptedModel
        let reply = AgentReplyModel()
        let speech = SilentSpeech()
        let task = AgentTaskContext(id: UUID(), tabID: UUID())

        init(turns: [ScriptedModel.Turn], maxToolCalls: Int = 4) {
            model = ScriptedModel(turns: turns)
            let log = ConversationLog(database: .temporary())
            agent = AnyLanguageModelAgent(
                name: "scripted",
                model: model,
                options: GenerationOptions(),
                budget: ContextBudget(
                    windowTokens: 8_192,
                    responseTokens: 1_024,
                    inputTokens: 6_144,
                    toolSchemaTokens: 0,
                    instructionTier: .full,
                    toolTier: .full,
                    toolOutput: .standard,
                    maxToolCalls: maxToolCalls,
                    retainedExchanges: 3,
                    retainedToolRounds: 3
                ),
                toolkit: AgentToolkit(
                    browser: BrowserModel(database: .temporary()),
                    media: MediaCenter(),
                    log: log,
                    services: .live
                ),
                log: log
            )
        }

        func run(_ utterance: String = "What is this?") async {
            await agent.run(utterance: utterance, task: task, into: reply, speech: speech)
        }
    }

    @Test func aPlainAnswerLandsInTheReply() async {
        let turn = Turn(turns: [.text("Paris.")])
        await turn.run("Where was it made?")

        #expect(turn.reply.text == "Paris.")
        #expect(turn.reply.activity == nil)
        #expect(turn.model.prompts == ["Where was it made?"])
        #expect(turn.speech.spoken.count == 1)
        #expect(turn.speech.spoken.first?.hasSuffix("Paris.") == true)
    }

    @Test func aToolRoundIsContinuedUntilTheModelSpeaks() async {
        let turn = Turn(turns: [.toolCall(named: "inspect"), .text("Done.")])
        await turn.run()

        #expect(turn.reply.text == "Done.")
        #expect(turn.model.prompts.count == 2)
        #expect(turn.model.prompts.last == "Continue the task using the tool result.")
    }

    @Test func aBarrenTurnIsAskedForTheAnswerDirectly() async {
        let turn = Turn(turns: [.text(""), .text("Here it is.")])
        await turn.run()

        #expect(turn.reply.text == "Here it is.")
        #expect(turn.model.prompts.last == "Answer the user now, in plain words.")
    }

    @Test func twoBarrenTurnsBecomeTheEmptyResponseError() async {
        let turn = Turn(turns: [.text(""), .text("")])
        await turn.run()

        #expect(
            turn.reply.text
                == "The model returned an empty response. Try again or choose another model."
        )
        #expect(turn.speech.spoken.isEmpty)
    }

    @Test func exhaustingTheToolBudgetGivesUpAudibly() async {
        let turn = Turn(
            turns: [.toolCall(named: "inspect"), .toolCall(named: "inspect")],
            maxToolCalls: 2
        )
        await turn.run()

        #expect(turn.reply.text == "This task needed more steps than expected. Try asking again.")
    }

    @Test func aContextWindowOverflowRetriesOnACleanSession() async {
        let overflow = LanguageModelSession.GenerationError.exceededContextWindowSize(
            .init(debugDescription: "scripted overflow")
        )
        let turn = Turn(turns: [.error(overflow), .text("Fresh start.")])
        await turn.run("Long question")

        #expect(turn.reply.text == "Fresh start.")
        #expect(turn.model.prompts == ["Long question", "Long question"])
    }

    @Test func anOnDeviceOverflowIsRecoveredLikeTheProviderOne() async {
        let turn = Turn(turns: [
            .toolCall(named: "inspect"),
            .error(SystemModelFailureTests.contextOverflow()),
            .text("Recovered."),
        ])
        await turn.run("Long task")

        #expect(turn.reply.text == "Recovered.")
    }

    @Test func anOverflowMidTurnIsRecoveredWithoutRestartingTheTask() async {
        let overflow = LanguageModelSession.GenerationError.exceededContextWindowSize(
            .init(debugDescription: "scripted overflow")
        )
        let turn = Turn(turns: [
            .toolCall(named: "inspect"),
            .error(overflow),
            .text("Recovered."),
        ])
        await turn.run("Long task")

        #expect(turn.reply.text == "Recovered.")
        #expect(turn.model.prompts == [
            "Long task",
            "Continue the task using the tool result.",
            "Continue the task using the tool result.",
        ])
    }

    @Test func aProviderFailureBecomesTheConnectionMessage() async {
        let turn = Turn(turns: [.error(URLError(.notConnectedToInternet))])
        await turn.run()

        #expect(
            turn.reply.text
                == "Couldn’t reach the model provider. Check its connection and API key in Settings."
        )
        #expect(turn.speech.spoken.isEmpty)
    }
}
