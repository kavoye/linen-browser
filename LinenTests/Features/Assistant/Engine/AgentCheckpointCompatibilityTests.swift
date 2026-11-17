// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

struct AgentCheckpointCompatibilityTests {
    static let fixture = Repository.root.appending(
        path: "LinenTests/Features/Assistant/Engine/Fixtures/AgentCheckpoint-AnyLanguageModel-1.0.0.json")

    static func checkpoint() throws -> AgentCheckpoint {
        let arguments = GeneratedContent(properties: [
            "value": "Ada Lovelace",
            "count": GeneratedContent(kind: .number(3)),
            "ratio": GeneratedContent(kind: .number(0.5)),
            "flags": GeneratedContent(kind: .array([GeneratedContent(kind: .bool(true)), GeneratedContent(kind: .bool(false))])),
            "nested": GeneratedContent(properties: ["note": "optional", "missing": GeneratedContent(kind: .null)]),
        ])
        let structured = GeneratedContent(properties: [
            "title": "Fixture form",
            "fields": GeneratedContent(kind: .array([GeneratedContent("name"), GeneratedContent("email")])),
        ])
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let toolDefinition = Transcript.ToolDefinition(tool: HarnessTool(name: "fillField", state: HarnessToolState()))
        let entries: [Transcript.Entry] = [
            .instructions(.init(
                id: "instructions",
                segments: [.text(.init(id: "instructions-text", content: "You are Linen’s browser assistant."))],
                toolDefinitions: [toolDefinition]
            )),
            .prompt(.init(
                id: "prompt",
                segments: [
                    .text(.init(id: "prompt-text", content: "Fill the fixture form")),
                    .image(.init(id: "prompt-image-data", data: png, mimeType: "image/png")),
                    .image(.init(id: "prompt-image-url", url: URL(string: "https://example.com/screenshot.png")!)),
                ],
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 512),
                responseFormat: .init(type: HarnessTool.Arguments.self)
            )),
            .reasoning(.init(
                id: "reasoning",
                metadata: ["provider": GeneratedContent("fixture")],
                segments: [.text(.init(id: "reasoning-text", content: "The form has two fields."))],
                signature: Data("fixture-signature".utf8)
            )),
            .toolCalls(.init(id: "tool-calls", [
                Transcript.ToolCall(id: "call-1", toolName: "fillField", arguments: arguments),
                Transcript.ToolCall(id: "call-2", toolName: "readPage", arguments: GeneratedContent(properties: [:]),
                                    providerMetadata: ["thought_signature": "fixture"]),
            ])),
            .toolOutput(.init(id: "call-1", toolName: "fillField", segments: [
                .text(.init(id: "output-text", content: "Filled the name field.")),
            ])),
            .toolOutput(.init(id: "call-2", toolName: "readPage", segments: [
                .structure(.init(id: "output-structure", source: "readPage", content: structured)),
                .image(.init(id: "output-image", data: png, mimeType: "image/png")),
            ])),
            .response(.init(id: "response", assetIDs: ["asset-1"], segments: [
                .text(.init(id: "response-text", content: "Filled the form.")),
                .structure(.init(id: "response-structure", source: "Answer", content: structured)),
            ])),
        ]
        return AgentCheckpoint(
            transcript: Transcript(entries: entries),
            summary: "The name field is filled.",
            request: "Fill the fixture form",
            userAnswers: ["Use my work email"],
            progressUpdates: [.init(id: UUID(uuidString: "7D2E1C1A-0000-4000-8000-000000000001")!, text: "Filling the form", afterStepCount: 1)],
            openAI: nil,
            memoryUpdates: nil
        )
    }

    @Test func checkpointSavedByAnyLanguageModel100StillDecodes() throws {
        let data = try Data(contentsOf: Self.fixture)
        let decoded = try JSONDecoder().decode(AgentCheckpoint.self, from: data)
        let expected = try Self.checkpoint()
        #expect(Array(decoded.transcript).map(\.id) == Array(expected.transcript).map(\.id))
        for (restored, original) in zip(decoded.transcript, expected.transcript) {
            #expect(restored == original, "\(original.id)")
        }
        #expect(decoded.summary == expected.summary)
        #expect(decoded.request == expected.request)
        #expect(decoded.userAnswers == expected.userAnswers)
        #expect(decoded.progressUpdates == expected.progressUpdates)
    }
}
