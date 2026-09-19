// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIComputerTests {
    static func call(_ actions: [OpenAIJSON] = [["type": "screenshot"]], id: String = "computer_1") -> OpenAIJSON {
        ["type": "computer_call", "id": "cu_item", "call_id": .string(id), "status": "completed", "actions": .array(actions), "pending_safety_checks": []]
    }

    @Test func nativeCallAndScreenshotRemainNativeAcrossContinuation() async throws {
        let raw = Self.call()
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([raw]), OpenAITransportFixture.response([OpenAITransportFixture.message("Verified.")])])
        var options = OpenAIResponseSettings()
        options.useComputer = true
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "validation-model", settings: options, transport: wire)
        let first = try await client.respond(transcript: Transcript(), prompt: "Inspect the page", images: [], state: client.restoring(nil), tools: [], maxTokens: 100, onText: { _ in })
        #expect(first.calls.first?.toolName == OpenAIComputerCall.toolName)
        var entries = Array(first.transcript)
        entries.append(.toolOutput(.init(id: "computer_1", toolName: OpenAIComputerCall.toolName, segments: [
            .text(.init(content: "{\"success\":true}")), .image(.init(data: Data([1, 2, 3]), mimeType: "image/jpeg")),
        ])))
        let second = try await client.respond(transcript: Transcript(entries: entries), prompt: "Continue", images: [], state: first.state, tools: [], maxTokens: 100, onText: { _ in })
        #expect(second.text == "Verified.")
        let body = try OpenAIJSON.decode(wire.requests[1].body!)
        #expect(body["tools"].array?.contains(["type": "computer"]) == true)
        let result = try #require(body["input"].array?.first { $0["type"] == "computer_call_output" })
        #expect(result["call_id"] == "computer_1")
        #expect(result["output"]["detail"] == "original")
        #expect(result["output"]["image_url"] == "data:image/jpeg;base64,AQID")
        #expect(body["input"].array?.filter { $0["type"] == "function_call_output" }.isEmpty == true)
        #expect(second.state.computerCallIDs == ["computer_1"])
    }

    @Test func unsupportedAndIncompleteActionsNeverBecomeProposals() throws {
        var incomplete = Self.call()
        incomplete["status"] = "in_progress"
        for raw in [incomplete, Self.call([]), Self.call([["type": "future_action"]]),
                    Self.call([["type": "click", "button": "left", "x": -1, "y": 0]]),
                    Self.call([["type": "scroll", "x": 0, "y": 0, "scroll_x": .integer(Int64.min), "scroll_y": 0]]), ] {
            #expect(throws: OpenAIFailure.self) { try OpenAIComputerCall(raw) }
        }
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([Self.call()])) }
        var forged = OpenAITransportFixture.call
        forged["name"] = .string(OpenAIComputerCall.toolName)
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([forged]), localDefinitions: [["type": "computer"]]) }
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([Self.call(), Self.call()]), localDefinitions: [["type": "computer"]]) }
        _ = try OpenAIComputerCall(Self.call([["type": "click", "button": "wheel", "x": .number(3.5), "y": .number(4.5), "keys": ["SHIFT"]]]))
    }

    @Test func interruptedCallsLeaveNoUnansweredWireItemButKeepReplayLedger() throws {
        let raw = Self.call()
        let call = try OpenAIComputerCall(raw).proposal()
        let transcript = Transcript(entries: [.toolCalls(.init([call]))])
        var state = OpenAIConversationState(binding: "fixture")
        try state.received(OpenAITransportFixture.response([raw]), transcript: transcript)
        var entries = Array(transcript)
        entries.append(.toolOutput(.init(id: call.id, toolName: call.toolName, segments: [.text(.init(content: "Interrupted."))])))
        let settled = try state.synchronizing(Transcript(entries: entries))
        #expect(!settled.items.contains(raw))
        #expect(settled.computerCallIDs == [call.id])
        #expect(settled.items.last?["role"] == "user")
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(settled))
        #expect(restored.computerCallIDs == [call.id])
    }

    @Test func safetyChecksRequireExplicitApprovalAndImage() throws {
        var raw = Self.call()
        raw["pending_safety_checks"] = [["id": "check_1", "code": "confirmation", "message": "Confirm the action"]]
        let call = try OpenAIComputerCall(raw)
        func output(_ approved: Bool, image: Bool) -> Transcript.ToolOutput {
            var segments: [Transcript.Segment] = [.text(.init(content: "{\"success\":true,\"safety_approved\":\(approved)}"))]
            if image { segments.append(.image(.init(data: Data([1]), mimeType: "image/png"))) }
            return .init(id: call.id, toolName: OpenAIComputerCall.toolName, segments: segments)
        }
        #expect(try call.result(output(false, image: true)) == nil)
        #expect(try call.result(output(true, image: false)) == nil)
        #expect(try call.result(output(true, image: true))?["acknowledged_safety_checks"] == raw["pending_safety_checks"])
    }

    @Test func settingsMigrationAndChangedModeResetNativeState() throws {
        let defaults = try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data("{}".utf8))
        #expect(!defaults.useComputer)
        var options = defaults
        options.useComputer = true
        let endpoint = URL(string: "https://api.openai.com/v1")!
        let enabled = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "validation-model", settings: options)
        let disabled = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "validation-model")
        var state = enabled.restoring(nil)
        state.items = [Self.call()]
        #expect(disabled.restoring(state).items.isEmpty)
    }

    @Test func compactionAndRestartDoNotAllowAComputerCallToReplay() async throws {
        let wire = OpenAITransportFixture([
            ["output": [["type": "compaction", "encrypted_content": "opaque"]]],
            OpenAITransportFixture.response([Self.call()]),
        ])
        var settings = OpenAIResponseSettings()
        settings.useComputer = true
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "validation-model", settings: settings, transport: wire)
        var state = client.restoring(nil)
        state.items = [Self.call()]
        state.computerCallIDs = ["computer_1"]
        let compacted = try await client.compact(state: state, instructions: "Continue")
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(compacted))
        #expect(restored.computerCallIDs == ["computer_1"])
        #expect(!restored.items.contains(Self.call()))
        await #expect(throws: OpenAIFailure.self) {
            try await client.respond(transcript: Transcript(), prompt: "Continue", images: [], state: restored, tools: [], maxTokens: 100, onText: { _ in })
        }
    }
}
