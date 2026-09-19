// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct HarnessAdapterTests {
    @Test(arguments: ["responses", "chat", "anthropic", "gemini"])
    func actualRemoteAdaptersReturnControlAfterEachProposal(_ variant: String) async throws {
        HarnessProviderProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HarnessProviderProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let endpoint = URL(string: "https://harness.invalid/v1")!
        let model: any LanguageModel
        switch variant {
        case "anthropic":
            model = AnthropicLanguageModel(baseURL: endpoint, apiKey: "fixture-key", model: "fixture", session: transport)
        case "gemini":
            model = GeminiLanguageModel(baseURL: endpoint, apiKey: "fixture-key", model: "fixture", session: transport)
        default:
            model = OpenAILanguageModel(
                baseURL: endpoint, apiKey: "fixture-key", model: "fixture",
                apiVariant: variant == "responses" ? .responses : .chatCompletions, session: transport
            )
        }
        let log = ConversationLog(database: .temporary())
        let state = HarnessToolState()
        let agent = AnyLanguageModelAgent(
            name: "fixture", executionPolicy: .interactive,
            toolOverrides: [HarnessTool(name: "readPage", state: state)], model: model,
            options: GenerationOptions(),
            budget: ContextBudget.resolve(windowTokens: 128_000, desiredResponseTokens: 2_000),
            toolkit: AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log), log: log
        )
        let tab = UUID()
        let id = log.beginTask("Read the fixture pages", tabID: tab)
        let reply = AgentReplyModel()
        await agent.run(utterance: "Read the fixture pages", task: .init(id: id, tabID: tab), into: reply, speech: HarnessSpeech())
        #expect(reply.text == "Fixture completed.")
        #expect(state.calls == 25)
        #expect(HarnessProviderProtocol.bodies.count == 26)
        #expect(log.latestTrace(forTab: tab)?.diagnostics.modelRequests == 26)
        #expect(HarnessProviderProtocol.bodies.dropFirst().allSatisfy { $0.contains("Observed state") })
        #expect(HarnessProviderProtocol.bodies.allSatisfy { !$0.contains("max_tool_calls") })
    }
}

private nonisolated final class HarnessProviderProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var requests: [String] = []

    static var bodies: [String] {
        lock.withLock { requests }
    }

    static func reset() {
        lock.withLock { requests = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "harness.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let index = Self.lock.withLock {
            Self.requests.append(String(decoding: data, as: UTF8.self))
            return Self.requests.count
        }
        let payload: [String: Any]
        let call = "call_\(index)"
        if request.url?.path.hasSuffix("responses") == true {
            let output: [[String: Any]] = index <= 25
                ? [["type": "function_call", "call_id": call, "id": "fc_\(index)", "name": "readPage", "arguments": "{\"value\":\"fixture\"}"]]
                : [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Fixture completed."]]]]
            payload = ["id": "response_\(index)", "output": output]
        } else if request.url?.path.hasSuffix("messages") == true {
            let content: [[String: Any]] = index <= 25
                ? [["type": "tool_use", "id": call, "name": "readPage", "input": ["value": "fixture"]]]
                : [["type": "text", "text": "Fixture completed."]]
            payload = ["id": "response_\(index)", "type": "message", "role": "assistant", "model": "fixture",
                       "content": content, "stop_reason": index <= 25 ? "tool_use" : "end_turn"]
        } else if request.url?.path.contains("generateContent") == true {
            let parts: [[String: Any]] = index <= 25
                ? [["functionCall": ["name": "readPage", "args": ["value": "fixture"]]]]
                : [["text": "Fixture completed."]]
            payload = ["candidates": [["content": ["role": "model", "parts": parts], "finishReason": "STOP"]]]
        } else {
            let message: [String: Any] = index <= 25
                ? ["role": "assistant", "tool_calls": [["id": call, "type": "function", "function": ["name": "readPage", "arguments": "{\"value\":\"fixture\"}"]]]]
                : ["role": "assistant", "content": "Fixture completed."]
            payload = ["id": "response_\(index)", "choices": [["message": message, "finish_reason": index <= 25 ? "tool_calls" : "stop"]]]
        }
        do {
            let output = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: output)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
