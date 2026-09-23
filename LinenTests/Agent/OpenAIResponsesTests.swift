// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

nonisolated final class OpenAITransportFixture: OpenAITransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [OpenAIJSON]
    private var failureStarts: Int
    private var eventErrorsBeforeSuccess: Int
    private let eventErrorCode: String?
    private let outputBeforeError: Bool
    private let streamEvents: [OpenAIEvent]?
    private var seen: [OpenAIRequest] = []
    var requests: [OpenAIRequest] {
        lock.withLock { seen }
    }
    init(_ responses: [OpenAIJSON], failureStarts: Int = 0, eventErrorsBeforeSuccess: Int = 0,
         eventErrorCode: String? = "server_error", outputBeforeError: Bool = false,
         streamEvents: [OpenAIEvent]? = nil) {
        self.responses = responses
        self.failureStarts = failureStarts
        self.eventErrorsBeforeSuccess = eventErrorsBeforeSuccess
        self.eventErrorCode = eventErrorCode
        self.outputBeforeError = outputBeforeError
        self.streamEvents = streamEvents
    }

    private func next(_ request: OpenAIRequest) throws -> OpenAIJSON {
        try lock.withLock {
            seen.append(request)
            if failureStarts > 0 {
                failureStarts -= 1
                throw OpenAIFailure(kind: .streamInterrupted)
            }
            guard !responses.isEmpty else { throw OpenAIFailure(kind: .streamInterrupted) }
            return responses.removeFirst()
        }
    }
    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        .init(data: try next(request).data(), status: 200, headers: [:])
    }
    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        AsyncThrowingStream { continuation in
            do {
                let eventError = lock.withLock { () -> Bool in
                    guard eventErrorsBeforeSuccess > 0 else { return false }
                    eventErrorsBeforeSuccess -= 1
                    seen.append(request)
                    return true
                }
                if eventError {
                    continuation.yield(.init(type: "response.created", payload: ["type": "response.created"], id: nil))
                    if outputBeforeError {
                        continuation.yield(.init(type: "response.output_text.delta", payload: ["delta": "Partial"], id: nil))
                    }
                    var payload: OpenAIJSON = ["type": "error"]
                    if let eventErrorCode { payload["code"] = .string(eventErrorCode) }
                    continuation.yield(.init(type: "error", payload: payload, id: nil))
                    continuation.finish()
                    return
                }
                let response = try next(request)
                if let streamEvents {
                    for event in streamEvents { continuation.yield(event) }
                } else {
                    continuation.yield(.init(type: "response.future_notification", payload: ["future": true], id: nil))
                    continuation.yield(.init(type: "response.output_text.delta", payload: ["delta": "Checking…"], id: nil))
                }
                continuation.yield(
                    .init(type: "response." + (response["status"].string ?? "completed"), payload: ["response": response], id: nil))
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }

    static var usage: OpenAIJSON {
        [
            "input_tokens": 100, "output_tokens": 20, "input_tokens_details": ["cached_tokens": 40, "cache_write_tokens": 5],
            "output_tokens_details": ["reasoning_tokens": 12], "total_tokens": 120,
        ]
    }
    static func response(_ output: [OpenAIJSON], status: String = "completed") -> OpenAIJSON {
        ["id": .string("resp-" + UUID().uuidString), "status": .string(status), "output": .array(output), "usage": usage]
    }
    static func message(_ text: String) -> OpenAIJSON {
        ["type": "message", "role": "assistant", "phase": "final_answer", "content": [["type": "output_text", "text": .string(text)]]]
    }
    static var call: OpenAIJSON {
        ["type": "function_call", "id": "item_call", "call_id": "call_read", "name": "readPage", "arguments": "{\"value\":\"fixture\"}"]
    }
    static var reasoning: OpenAIJSON {
        [
            "type": "reasoning", "id": "rs_private", "encrypted_content": "opaque-private-state", "summary": [],
            "future_field": ["preserve": true],
        ]
    }
}

@MainActor
struct OpenAIResponsesTests {
    @Test func progressToolArgumentsStreamBeforeTheResponseCompletes() async throws {
        let message = "I'll inspect the page."
        let arguments = #"{"message":"I'll inspect the page."}"#
        let call: OpenAIJSON = [
            "type": "function_call", "id": "item_progress", "call_id": "call_progress",
            "name": "updateProgress", "arguments": .string(arguments),
        ]
        let events: [OpenAIEvent] = [
            .init(type: "response.output_item.added", payload: [
                "output_index": 0, "item": ["type": "function_call", "name": "updateProgress", "arguments": ""],
            ], id: nil),
            .init(type: "response.function_call_arguments.delta", payload: [
                "output_index": 0, "delta": #"{"message":"I'll inspect"#,
            ], id: nil),
            .init(type: "response.function_call_arguments.delta", payload: [
                "output_index": 0, "delta": #" the page."}"#,
            ], id: nil),
            .init(type: "response.function_call_arguments.done", payload: [
                "output_index": 0, "arguments": .string(arguments),
            ], id: nil),
        ]
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([call])], streamEvents: events)
        var visible: [String] = []
        let client = client(wire)
        let step = try await client.respond(
            transcript: Transcript(), prompt: "Inspect", images: [], state: client.restoring(nil),
            tools: [UpdateProgressTool()], maxTokens: 100, onText: { _ in }, onProgress: { visible.append($0) }
        )
        #expect(visible.first == "I'll inspect")
        #expect(visible.last == message)
        #expect(step.calls.map(\.toolName) == ["updateProgress"])
    }

    @Test func partialProgressDecodesEscapesOnlyWhenComplete() {
        #expect(OpenAIProgressMessage.partial(#"{"message":"Wait \"#) == "Wait ")
        #expect(OpenAIProgressMessage.partial(#"{"message":"Wait \uD83D"#) == "Wait ")
        #expect(OpenAIProgressMessage.partial(#"{"message":"Wait \uD83D\uDE00"#) == "Wait 😀")
        #expect(OpenAIProgressMessage.partial(#"{"other":"secret"}"#) == nil)
    }

    @Test func imageOnlyResponsesFinishWithoutASecondGeneration() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([
            ["type": "image_generation_call", "id": "image_fixture", "result": "AQID", "output_format": "png"],
        ]), ])
        let fixture = HarnessFixture([], openAI: client(wire))
        await fixture.run("Generate an image")
        #expect(wire.requests.count == 1)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .completed)
        #expect(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI?.presentation?.pictures.count == 1)
    }

    private func client(_ fixture: OpenAITransportFixture) -> OpenAIResponsesClient {
        .init(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "validation-model", transport: fixture)
    }

    @Test func nativeStateSurvivesToolBoundariesAndRestartWithoutDuplicateCalls() async throws {
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAITransportFixture.reasoning, OpenAITransportFixture.call]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Verified.")]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Continued.")]),
        ])
        let fixture = HarnessFixture([], openAI: client(wire))
        let first = await fixture.run()
        #expect(fixture.state.calls == 1)
        #expect(fixture.reply.text == "Verified.")
        let secondBody = try OpenAIJSON.decode(wire.requests[1].body!)
        let items = try #require(secondBody["input"].array)
        #expect(items.contains(OpenAITransportFixture.reasoning))
        #expect(items.filter { $0["type"].string == "function_call" }.count == 1)
        let result = try #require(items.first { $0["type"].string == "function_call_output" })
        #expect(result["call_id"] == "call_read")
        #expect(result["output"].array?.first?["text"].string == "Observed state 1")
        #expect(secondBody["store"] == false)
        #expect(secondBody["tools"].array?.first?["parameters"]["type"] == "object")
        #expect(secondBody["tools"].array?.first?["strict"] == true)
        let diagnostics = try #require(fixture.log.traces.first { $0.id == first }?.diagnostics)
        #expect(diagnostics.inputTokens == 200)
        #expect(diagnostics.outputTokens == 40)
        #expect(diagnostics.cachedTokens == 80)
        #expect(diagnostics.cacheWriteTokens == 10)
        #expect(diagnostics.reasoningTokens == 24)
        #expect(diagnostics.events.contains { $0.kind == "first_text" && Int($0.values["elapsed_ms"] ?? "") != nil })
        #expect(fixture.log.usage(forTab: fixture.tabID).requestCount == 2)
        #expect(fixture.log.usage(forTab: fixture.tabID).inputTokens == 200)
        #expect(!diagnostics.exported().contains("opaque-private-state"))
        let saved = try JSONDecoder().decode(
            AgentCheckpoint.self, from: JSONEncoder().encode(fixture.log.checkpoint(forTab: fixture.tabID)))
        #expect(saved.openAI?.items.contains(OpenAITransportFixture.reasoning) == true)
        let restored = HarnessFixture([], database: fixture.database, tabID: fixture.tabID, openAI: client(wire))
        await restored.run("Continue", isContinuation: true)
        #expect(restored.state.calls == 0)
        #expect(restored.reply.text == "Continued.")
        let resumed = try OpenAIJSON.decode(wire.requests[2].body!)
        #expect(resumed["input"].array?.contains(OpenAITransportFixture.reasoning) == true)
        #expect(resumed["input"].array?.contains(where: { $0["phase"] == "final_answer" }) == true)
    }

    @Test func incompleteToolResponseNeverExecutesAnAction() async throws {
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAITransportFixture.call], status: "incomplete"),
            OpenAITransportFixture.response([OpenAITransportFixture.message("No action was completed.")]),
        ])
        let fixture = HarnessFixture([], openAI: client(wire))
        await fixture.run()
        #expect(fixture.state.calls == 0)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .providerError)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.diagnostics.inputTokens == 200)
    }

    @Test func compactionPreservesTheCanonicalWindowAndUsage() async throws {
        let compacted: [OpenAIJSON] = [
            ["type": "message", "role": "user", "content": "Keep this"],
            ["type": "compaction", "encrypted_content": "private_compaction", "new_field": 1],
        ]
        let wire = OpenAITransportFixture([["output": .array(compacted), "usage": OpenAITransportFixture.usage]])
        var state = client(wire).restoring(nil)
        state.items = [OpenAITransportFixture.reasoning]
        let result = try await client(wire).compact(state: state, instructions: "Current rules")
        #expect(result.items == compacted)
        #expect(result.contextTokens == 20)
        #expect(wire.requests.first?.path == ["responses", "compact"])
    }

    @Test func missingUsageNeverBecomesAZeroOrCompleteTotal() {
        var diagnostics = AgentRunDiagnostics()
        diagnostics.record(.init(kind: "provider_usage", values: [:]))
        diagnostics.record(.init(kind: "provider_usage", values: OpenAIUsage(raw: OpenAITransportFixture.usage).eventValues))
        #expect(diagnostics.inputTokens == nil)
        #expect(diagnostics.cacheWriteTokens == nil)
        #expect(diagnostics.providerUsageRequests == 2)
        #expect(OpenAIUsage(raw: ["input_tokens": -1]).input == nil)
    }

    @Test func unknownActionsAreNotReportedAsCompletedWork() throws {
        #expect(throws: OpenAIFailure.self) {
            try OpenAIModelStep.output(OpenAITransportFixture.response([["type": "future_dangerous_call", "action": "write"]]))
        }
    }

    @Test func unknownFieldsAndLargeIntegersRoundTrip() throws {
        let value = try OpenAIJSON.decode(Data(#"{"number":9007199254740993,"future":{"list":[true,null,3.5]}}"#.utf8))
        #expect(try OpenAIJSON.decode(value.data()) == value)
        #expect(value["number"] == .integer(9_007_199_254_740_993))
    }

    @Test func endpointBindingSeparatesModelsAndHosts() {
        let old = client(.init([])).restoring(nil)
        let other = OpenAIResponsesClient(endpoint: URL(string: "https://other.example/v1")!, apiKey: "fixture", model: "validation-model")
        #expect(other.restoring(old).binding != old.binding)
        #expect(other.restoring(old).items.isEmpty)
        let changedAccount = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "different-account", model: "validation-model")
        #expect(changedAccount.restoring(old).binding != old.binding)
        #expect(!changedAccount.binding.contains("different-account"))
    }

    @Test func sseSupportsCommentsMultilinePayloadsAndUnknownEvents() throws {
        var parser = OpenAISSEParser()
        #expect(try parser.consume(": heartbeat") == nil)
        #expect(try parser.consume("id: event_12") == nil)
        #expect(try parser.consume("event: response.future") == nil)
        #expect(try parser.consume("data: {\"type\":\"response.future\",") == nil)
        #expect(try parser.consume("data: \"payload\":{\"untouched\":true}}") == nil)
        let parsedEvent = try parser.consume("")
        let event = try #require(parsedEvent)
        #expect(event.type == "response.future")
        #expect(event.payload["payload"]["untouched"] == true)
        #expect(event.id == "event_12")
        #expect(try parser.consume("data: [DONE]") == nil)
        #expect(try parser.consume("") == nil)
    }

    @Test func sseHTTPAndMissingTerminalAreHandled() async throws {
        let terminal = try OpenAITransportFixture.response([OpenAITransportFixture.message("Ready")]).text()
        let valid = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
            + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Ready\"}\n\n"
            + "event: response.completed\ndata: {\"response\":\(terminal)}\n\n"
        let server = try await HTTPFixtureServer.start(routes: [
            "/v1/responses": .bytes(Data(valid.utf8), contentType: "text/event-stream"),
            "/incomplete/responses": .bytes(
                Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\n".utf8), contentType: "text/event-stream"),
        ])
        let api = OpenAIAPI(transport: OpenAIHTTPTransport(baseURL: try server.url("/v1"), apiKey: "fixture"))
        let response = try await api.createResponse([:]) { _ in }
        #expect(response["status"] == "completed")
        let broken = OpenAIAPI(transport: OpenAIHTTPTransport(baseURL: try server.url("/incomplete"), apiKey: "fixture"))
        await #expect(throws: OpenAIFailure.self) { try await broken.createResponse([:]) { _ in } }
    }

    @Test func sseByteFramingPreservesDelimitersAndUnicode() throws {
        for newline in ["\n", "\r\n", "\r"] {
            var framer = OpenAISSEFramer()
            let source = "\u{FEFF}: heartbeat\(newline)\(newline)"
                + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"café 🌱\"}\(newline)\(newline)"
                + "data: {\"type\":\"response.completed\",\"response\":{}}\(newline)\(newline)"
                + "data: [DONE]\(newline)\(newline)"
            var events: [OpenAIEvent] = []
            for byte in source.utf8 {
                if let event = try framer.consume(byte) {
                    events.append(event)
                }
            }
            #expect(try framer.finish() == nil)
            #expect(events.map(\.type) == ["response.output_text.delta", "response.completed"])
            #expect(events.first?.payload["delta"] == "café 🌱")
        }
    }
}
