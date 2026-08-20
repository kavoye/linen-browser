// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentContextCompactionTests {
    private final class RecordingModel: LanguageModel, @unchecked Sendable {
        enum Turn {
            case text(String)
            case toolCall
        }

        private let lock = NSLock()
        private var turns: [Turn]
        private var seen: [[String]] = []

        init(turns: [Turn]) {
            self.turns = turns
        }

        var transcripts: [[String]] {
            lock.withLock { seen }
        }

        private func next(recording transcript: [String]) -> Turn {
            lock.withLock {
                seen.append(transcript)
                return turns.isEmpty ? .text("done") : turns.removeFirst()
            }
        }

        func respond<Content>(
            within session: LanguageModelSession,
            to prompt: Prompt,
            generating type: Content.Type,
            includeSchemaInPrompt: Bool,
            options: GenerationOptions
        ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
            switch next(recording: Self.flatten(session.transcript)) {
            case .text(let text):
                guard let content = text as? Content else {
                    fatalError("the recording model only generates String")
                }
                return .init(
                    content: content,
                    rawContent: GeneratedContent(text),
                    transcriptEntries: []
                )
            case .toolCall:
                let call = Transcript.ToolCall(
                    id: UUID().uuidString,
                    toolName: "readPage",
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
                            toolName: "readPage",
                            segments: [.text(.init(content: String(repeating: "page text. ", count: 40)))]
                        )
                        await delegate.didExecuteToolCall(call, output: output, in: session)
                        entries.append(.toolOutput(output))
                    }
                }
                guard let content = "" as? Content else {
                    fatalError("the recording model only generates String")
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
                fatalError("the recording model only generates String")
            }
            return .init(content: content, rawContent: GeneratedContent(""))
        }

        private static func flatten(_ transcript: Transcript) -> [String] {
            transcript.map { entry in
                switch entry {
                case .instructions(let value):
                    "instructions: " + text(in: value.segments)
                case .prompt(let value):
                    "prompt: " + text(in: value.segments)
                case .response(let value):
                    "response: " + text(in: value.segments)
                case .toolCalls(let calls):
                    "toolCalls: " + calls.map(\.toolName).joined(separator: ",")
                case .toolOutput(let value):
                    "toolOutput: " + text(in: value.segments)
                }
            }
        }

        private static func text(in segments: [Transcript.Segment]) -> String {
            segments.compactMap { segment in
                if case .text(let text) = segment {
                    return text.content
                }
                return nil
            }.joined()
        }
    }

    private final class SilentSpeech: SpeechOutput {
        var isMuted = false
        var onSpeakingChange: ((Bool) -> Void)?

        func speak(_ text: String) {}
        func stopSpeaking() {}
    }

    private static func budget(
        inputTokens: Int,
        retainedToolRounds: Int = 1,
        maxToolCalls: Int = 6
    ) -> ContextBudget {
        ContextBudget(
            windowTokens: 4_096,
            responseTokens: 1_024,
            inputTokens: inputTokens,
            toolSchemaTokens: 0,
            instructionTier: .compact,
            toolTier: .core,
            toolOutput: ContextBudget.ToolOutputBudget(pageTextCharacters: 800, controlLimit: 12),
            maxToolCalls: maxToolCalls,
            retainedExchanges: 2,
            retainedToolRounds: retainedToolRounds
        )
    }

    private static func agent(
        model: any LanguageModel,
        budget: ContextBudget
    ) -> AnyLanguageModelAgent {
        let log = ConversationLog(database: .temporary())
        return AnyLanguageModelAgent(
            name: "recording",
            model: model,
            options: GenerationOptions(),
            budget: budget,
            toolkit: AgentToolkit(
                browser: BrowserModel(database: .temporary()),
                media: MediaCenter(),
                log: log
            ),
            log: log
        )
    }

    @Test func aTightBudgetTrimsToolRoundsButKeepsTheQuestion() async {
        let model = RecordingModel(turns: [.toolCall, .toolCall, .toolCall, .text("Found it.")])
        let subject = Self.agent(model: model, budget: Self.budget(inputTokens: 1))
        let reply = AgentReplyModel()

        await subject.run(
            utterance: "What is the first item here?",
            task: AgentTaskContext(id: UUID(), tabID: UUID()),
            into: reply,
            speech: SilentSpeech()
        )

        #expect(reply.text == "Found it.")

        let transcripts = model.transcripts
        #expect(transcripts.count == 4)

        for transcript in transcripts.dropFirst() {
            #expect(
                transcript.contains { $0.contains("What is the first item here?") },
                "the user's question was compacted away"
            )
            #expect(
                transcript.filter { $0.hasPrefix("toolOutput:") }.count <= 1,
                "more than one tool round survived a one-round budget"
            )
        }

        let sizes = transcripts.map(\.count)
        #expect(sizes.max() ?? 0 <= (sizes.first ?? 0) + 4, "the transcript grew unbounded")
    }

    @Test func aRoomyBudgetLeavesTheTranscriptIntact() async {
        let model = RecordingModel(turns: [.toolCall, .toolCall, .text("All good.")])
        let subject = Self.agent(model: model, budget: Self.budget(inputTokens: 100_000))
        let reply = AgentReplyModel()

        await subject.run(
            utterance: "Compare these two pages",
            task: AgentTaskContext(id: UUID(), tabID: UUID()),
            into: reply,
            speech: SilentSpeech()
        )

        #expect(reply.text == "All good.")

        let transcripts = model.transcripts
        let outputsInFinalCall = transcripts.last?.filter { $0.hasPrefix("toolOutput:") }.count ?? 0
        #expect(outputsInFinalCall == 2, "both tool rounds should still be present")
    }

    @Test func compactionTruncatesTheToolOutputItKeeps() async {
        let model = RecordingModel(turns: [.toolCall, .toolCall, .text("Trimmed.")])
        let subject = Self.agent(model: model, budget: Self.budget(inputTokens: 1))
        let reply = AgentReplyModel()

        await subject.run(
            utterance: "Read this",
            task: AgentTaskContext(id: UUID(), tabID: UUID()),
            into: reply,
            speech: SilentSpeech()
        )

        let kept = model.transcripts.last?.first { $0.hasPrefix("toolOutput:") }
        let body = kept.map { $0.replacingOccurrences(of: "toolOutput: ", with: "") }
        #expect(body != nil)
        #expect((body?.count ?? .max) <= 400, "kept tool output was not truncated to the budget")
    }
}
