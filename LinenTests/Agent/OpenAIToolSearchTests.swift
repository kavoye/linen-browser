// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIToolSearchTests {
    @Test func catalogPreservesEnabledToolsAndStrictSchemas() throws {
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()))
        let tools = makeAgentTools(toolkit: toolkit) + [UpdateProgressTool()]
        let definitions = try tools.map { tool -> OpenAIJSON in
            ["type": "function", "name": .string(tool.name), "description": .string(tool.description),
             "parameters": try OpenAISchema.strict(tool.parameters, dependencies: OpenAISchema.browserDependencies), "strict": true,
            ]
        }
        let deferred = OpenAIToolSearch.definitions(definitions, enabled: true)
        let flattened = deferred.flatMap { $0["type"] == "namespace" ? ($0["tools"].array ?? []) : ($0["type"] == "function" ? [$0] : []) }
        #expect(flattened.count == definitions.count)
        for definition in definitions {
            let actual = try #require(flattened.first { $0["name"] == definition["name"] })
            #expect(actual["parameters"] == definition["parameters"])
            #expect(actual["strict"] == true)
        }
        for namespace in deferred.filter({ $0["type"] == "namespace" }) {
            #expect((namespace["tools"].array?.count ?? 0) < 10)
            #expect(namespace["tools"].array?.allSatisfy { $0["defer_loading"] == true } == true)
        }
        #expect(deferred.contains { $0["type"] == "function" && $0["name"] == "askUser" })
        #expect(deferred.contains { $0["type"] == "function" && $0["name"] == "updateProgress" })
        let subset = definitions.filter { $0["name"] == "listTabs" }
        let reduced = OpenAIToolSearch.definitions(subset, enabled: true)
        #expect(reduced.first?["tools"].array?.map { $0["name"] } == ["listTabs"])
        #expect(OpenAIToolSearch.definitions([], enabled: true).isEmpty)
        #expect(OpenAIToolSearch.definitions(definitions, enabled: false) == definitions)
    }

    @Test func compatibleModelsAndSettingsKeepExistingBehaviorUntilEnabled() throws {
        for model in ["gpt-5.4", "gpt-5.6-luna", "gpt-6-astra", "gpt-5.4-2026-03-05"] { #expect(OpenAIToolSearch.supports(model)) }
        for model in ["gpt-5", "gpt-5.3-codex", "gpt-4.1", "o3", "custom", "gpt-unknown"] { #expect(!OpenAIToolSearch.supports(model)) }
        #expect(try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data("{}".utf8)).useToolSearch == false)
        var settings = OpenAIResponseSettings()
        let plain = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings)
        settings.useToolSearch = true
        let deferred = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings)
        #expect(plain.binding != deferred.binding)
        #expect(deferred.restoring(plain.restoring(nil)).items.isEmpty)
        let legacy = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-4.1", settings: settings)
        #expect(try legacy.body(state: legacy.restoring(nil), instructions: "", tools: [definition], maxTokens: 100)["tools"] == .array([definition]))
        #expect(try deferred.body(state: deferred.restoring(nil), instructions: "", tools: [], maxTokens: 100)["tools"] == [])
    }

    @Test func clientSearchAndUnconfirmedSearchAreNotSilentlyIgnored() throws {
        for type in ["tool_search_call", "tool_search_output"] {
            for execution in ["client", "server", "unknown"] {
                var item: OpenAIJSON = ["type": .string(type), "execution": .string(execution), "status": "completed", "call_id": .null]
                if execution == "server" {
                    #expect(try OpenAIModelStep.output(OpenAITransportFixture.response([item])).calls.isEmpty)
                } else {
                    #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([item])) }
                }
                item["status"] = "in_progress"
                #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([item])) }
            }
        }
    }

    @Test func namespacedCallsCannotResolveIntoAnotherOrDisabledNamespace() throws {
        let definitions = OpenAIToolSearch.definitions([definition], enabled: true)
        var call = functionCall
        #expect(try OpenAIModelStep.output(OpenAITransportFixture.response([call]), localDefinitions: definitions).calls.first?.toolName == "listTabs")
        call["namespace"] = "untrusted_server"
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([call]), localDefinitions: definitions) }
        call["namespace"] = 42
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([call]), localDefinitions: definitions) }
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(OpenAITransportFixture.response([functionCall]), localDefinitions: []) }
    }

    @Test func nativeDiscoveryAndNamespaceSurviveAStatelessContinuation() async throws {
        let search: OpenAIJSON = ["type": "tool_search_call", "execution": "server", "status": "completed", "call_id": .null, "arguments": ["query": "List tabs"]]
        let loaded: OpenAIJSON = ["type": "tool_search_output", "execution": "server", "status": "completed", "call_id": .null,
                                  "tools": .array(OpenAIToolSearch.definitions([definition], enabled: true).filter { $0["type"] == "namespace" }),
        ]
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([search, loaded, functionCall]), OpenAITransportFixture.response([OpenAITransportFixture.message("Done")])])
        var settings = OpenAIResponseSettings()
        settings.useToolSearch = true
        let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings, transport: wire)
        let tool = HarnessTool(name: "listTabs", state: HarnessToolState())
        let first = try await client.respond(transcript: Transcript(), prompt: "List tabs", images: [], state: client.restoring(nil), tools: [tool], maxTokens: 100, onText: { _ in })
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(first.state))
        var entries = Array(first.transcript)
        entries.append(.toolOutput(.init(id: "call_tabs", toolName: "listTabs", segments: [.text(.init(content: "No tabs"))])))
        _ = try await client.respond(transcript: Transcript(entries: entries), prompt: "Continue", images: [], state: restored, tools: [tool], maxTokens: 100, onText: { _ in })
        let input = try OpenAIJSON.decode(try #require(wire.requests.last?.body))["input"].array ?? []
        #expect(input.contains(search) && input.contains(loaded) && input.contains(functionCall))
        #expect(input.filter { $0["type"] == "function_call_output" }.count == 1)
        #expect(input.first { $0["type"] == "function_call_output" }?["call_id"] == "call_tabs")
    }

    @Test func namespacedToolRunsThroughTheProductionAgentExecutor() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([functionCall]), OpenAITransportFixture.response([OpenAITransportFixture.message("Done")])])
        var settings = OpenAIResponseSettings()
        settings.useToolSearch = true
        let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings, transport: wire)
        let log = ConversationLog(database: .temporary())
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log)
        let state = HarnessToolState()
        let agent = AnyLanguageModelAgent(
            name: "fixture", modelID: "gpt-5.6-luna", reasoningEffort: "low", executionPolicy: .init(maxModelRequests: 2),
            toolOverrides: [HarnessTool(name: "listTabs", state: state)], openAI: client, model: HarnessScript([]), options: GenerationOptions(),
            budget: ContextBudget(windowTokens: 128_000, responseTokens: 2_000, inputTokens: 100_000, toolSchemaTokens: 0,
                                  instructionTier: .compact, toolTier: .full, toolOutput: .standard, retainedExchanges: 12, retainedToolRounds: 1),
            toolkit: toolkit, log: log
        )
        let tabID = UUID()
        let id = log.beginTask("List tabs", tabID: tabID)
        let reply = AgentReplyModel()
        await agent.run(utterance: "List tabs", task: .init(id: id, tabID: tabID), into: reply, speech: HarnessSpeech())
        #expect(state.calls == 1)
        #expect(reply.text == "Done")
        let input = try OpenAIJSON.decode(try #require(wire.requests.last?.body))["input"].array ?? []
        #expect(input.contains(functionCall))
        #expect(input.first { $0["type"] == "function_call_output" }?["call_id"] == "call_tabs")
    }

    private var endpoint: URL { URL(string: "https://api.example.test/v1")! }
    private var definition: OpenAIJSON { ["type": "function", "name": "listTabs", "parameters": ["type": "object"], "strict": true] }
    private var functionCall: OpenAIJSON {
        ["type": "function_call", "call_id": "call_tabs", "name": "listTabs", "namespace": "browser_tabs", "arguments": "{\"value\":\"fixture\"}"]
    }
}
