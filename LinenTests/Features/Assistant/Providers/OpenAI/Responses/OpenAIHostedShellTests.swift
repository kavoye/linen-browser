// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIHostedShellTests {
    static var call: OpenAIJSON {
        ["type": "shell_call", "id": "sh_item", "call_id": "sh_call", "status": "completed",
         "environment": ["type": "container_reference", "container_id": "cntr_fixture"],
         "action": ["commands": ["printf private-shell-output"], "timeout_ms": 1_000, "max_output_length": 100],
         "future_field": ["retain": true], ]
    }
    static var output: OpenAIJSON {
        ["type": "shell_call_output", "id": "sh_output", "call_id": "sh_call", "status": "completed", "max_output_length": 100,
         "output": [["stdout": "private-shell-output", "stderr": "", "outcome": ["type": "exit", "exit_code": 0]]], ]
    }

    private func client(_ wire: OpenAITransportFixture, tool: OpenAIJSON? = OpenAIHostedShell.definition) -> OpenAIResponsesClient {
        var options = OpenAIResponseSettings()
        options.hostedTools = tool.map { [$0] } ?? []
        return .init(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "validation-model", settings: options, transport: wire)
    }

    @Test func hostedSettingsPreserveOptionsAndRejectLocalExecution() throws {
        var options = OpenAIResponseSettings()
        options.hostedTools = [["type": "shell", "environment": ["type": "container_auto", "memory_limit": "4g",
            "network_policy": ["type": "allowlist", "allowed_domains": ["example.com"]], ], ], ]
        try options.validate()
        #expect(try JSONDecoder().decode(OpenAIResponseSettings.self, from: JSONEncoder().encode(options)) == options)
        for bad in [
            ["type": "shell"], ["type": "shell", "environment": ["type": "local"]],
            ["type": "shell", "environment": ["type": "container_reference", "container_id": ""]],
        ] as [OpenAIJSON] {
            options.hostedTools = [bad]
            #expect(throws: OpenAISettingsError.self) { try options.validate() }
        }
        options.hostedTools = [OpenAIHostedShell.definition, OpenAIHostedShell.definition]
        #expect(throws: OpenAISettingsError.self) { try options.validate() }
    }

    @Test func nativeShellRoundTripAndRestartReuseContainerWithoutLocalExecution() async throws {
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([Self.call, Self.output, OpenAITransportFixture.message("Created the file.")]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Continued.")]),
        ])
        let fixture = HarnessFixture([], openAI: client(wire))
        let taskID = await fixture.run("Create a file in the hosted container")
        #expect(fixture.reply.text == "Created the file.")
        #expect(fixture.state.calls == 0)
        let saved = try #require(fixture.log.checkpoint(forTab: fixture.tabID))
        let restored = try JSONDecoder().decode(AgentCheckpoint.self, from: JSONEncoder().encode(saved))
        #expect(restored.openAI?.items.contains(Self.call) == true)
        #expect(restored.openAI?.items.contains(Self.output) == true)
        #expect(restored.openAI?.shellContainerID == "cntr_fixture")
        let diagnostics = try #require(fixture.log.traces.first { $0.id == taskID }?.diagnostics)
        #expect(!diagnostics.exported().contains("private-shell-output"))
        #expect(diagnostics.inputTokens == 100)
        let continuation = HarnessFixture([], database: fixture.database, tabID: fixture.tabID, openAI: client(wire))
        await continuation.run("Continue", isContinuation: true)
        let body = try OpenAIJSON.decode(wire.requests[1].body!)
        #expect(body["tools"].array?.first(where: { $0["type"] == "shell" })?["environment"] == Self.call["environment"])
        #expect(body["input"].array?.filter { $0 == Self.call }.count == 1)
        #expect(body["input"].array?.filter { $0 == Self.output }.count == 1)
        #expect(continuation.state.calls == 0)
    }

    @Test func environmentChangesResetContinuation() throws {
        let wire = OpenAITransportFixture([])
        let original = client(wire)
        var state = original.restoring(nil)
        state.items = [Self.call, Self.output]
        let changed = client(wire, tool: ["type": "shell", "environment": ["type": "container_auto", "memory_limit": "4g"]])
        #expect(changed.restoring(state).items.isEmpty)
        #expect(client(wire, tool: nil).restoring(state).items.isEmpty)
        let originalBody = try original.body(state: state, instructions: "", tools: [], maxTokens: 100)
        #expect(originalBody["tools"].array?.first?["environment"] == Self.call["environment"])
    }

    @Test func nullableEnvironmentPreservesHostedOutputWithoutInventingContainerIdentity() throws {
        var call = Self.call
        call["environment"] = .null
        let response = OpenAITransportFixture.response([call, Self.output])
        #expect(try OpenAIModelStep.output(response, localDefinitions: [OpenAIHostedShell.definition]).calls.isEmpty)
        var state = OpenAIConversationState(binding: "fixture")
        state.items = [call, Self.output]
        #expect(OpenAIHostedShell.definitions([OpenAIHostedShell.definition], state: state) == [OpenAIHostedShell.definition])
    }

    @Test func compactionRetainsContainerAfterShellItemsLeaveTheWindow() async throws {
        let wire = OpenAITransportFixture([["output": [["type": "compaction", "encrypted_content": "opaque-compacted-state"]]]])
        let client = client(wire)
        var state = client.restoring(nil)
        try state.received(OpenAITransportFixture.response([Self.call, Self.output]), transcript: Transcript())
        let compacted = try await client.compact(state: state, instructions: "Continue the task")
        #expect(!compacted.items.contains(Self.call))
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(compacted))
        let body = try client.body(state: restored, instructions: "Continue", tools: [], maxTokens: 100)
        #expect(body["tools"].array?.first?["environment"] == Self.call["environment"])
    }

    @Test func invalidShellResultsRejectEntireResponseBeforeLocalActions() async throws {
        var local = Self.call
        local["environment"] = ["type": "local"]
        var incomplete = Self.call
        incomplete["status"] = "in_progress"
        var orphan = Self.output
        orphan["call_id"] = "unknown"
        var unknownOutcome = Self.output
        unknownOutcome["output"] = [["stdout": "", "stderr": "", "outcome": ["type": "unknown"]]]
        var duplicate = Self.call
        duplicate["call_id"] = OpenAITransportFixture.call["call_id"]
        var duplicateOutput = Self.output
        duplicateOutput["call_id"] = duplicate["call_id"]
        for items in [[local, Self.output], [incomplete, Self.output], [Self.call], [Self.output],
                      [Self.call, orphan], [Self.call, Self.output, Self.output], [Self.call, Self.call, Self.output],
                      [Self.call, unknownOutcome], [duplicate, duplicateOutput], ] {
            let wire = OpenAITransportFixture([OpenAITransportFixture.response(items + [OpenAITransportFixture.call])])
            let fixture = HarnessFixture([], openAI: client(wire))
            await fixture.run()
            #expect(fixture.state.calls == 0)
            #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state != .completed)
        }
        #expect(throws: OpenAIFailure.self) {
            try OpenAIModelStep.output(OpenAITransportFixture.response([Self.call, Self.output]))
        }
    }

    @Test func mismatchedContainerAndRepeatedCallsAreRejected() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([Self.call, Self.output, OpenAITransportFixture.message("Done.")])])
        let wrong = client(wire, tool: ["type": "shell", "environment": ["type": "container_reference", "container_id": "cntr_other"]])
        await #expect(throws: OpenAIFailure.self) {
            try await wrong.respond(transcript: Transcript(), prompt: "Run", images: [], state: wrong.restoring(nil), tools: [], maxTokens: 100, onText: { _ in })
        }
        let repeated = OpenAITransportFixture([OpenAITransportFixture.response([Self.call, Self.output])])
        let client = client(repeated)
        var state = client.restoring(nil)
        state.items = [Self.call, Self.output]
        await #expect(throws: OpenAIFailure.self) {
            try await client.respond(transcript: Transcript(), prompt: "Run", images: [], state: state, tools: [], maxTokens: 100, onText: { _ in })
        }
    }

    @Test func nonzeroExitAndTimeoutAreValidObservationsAndFilesRemainDownloadable() throws {
        for outcome in [["type": "exit", "exit_code": 2], ["type": "timeout"]] as [OpenAIJSON] {
            var output = Self.output
            output["output"] = [["stdout": "", "stderr": "Command did not succeed", "outcome": outcome]]
            let response = OpenAITransportFixture.response([Self.call, output, OpenAITransportFixture.message("The command failed.")])
            let result = try OpenAIModelStep.output(response, localDefinitions: [OpenAIHostedShell.definition])
            #expect(result.calls.isEmpty)
            #expect(result.text == "The command failed.")
        }
        var presentation = OpenAIPresentation()
        presentation.append(OpenAITransportFixture.response([["type": "message", "content": [["type": "output_text", "text": "Download",
            "annotations": [["type": "container_file_citation", "container_id": "cntr_fixture", "file_id": "file_fixture", "filename": "result.csv"]], ], ], ], ]))
        #expect(presentation.files.first?.containerID == "cntr_fixture")
        #expect(presentation.files.first?.name == "result.csv")
    }
}
