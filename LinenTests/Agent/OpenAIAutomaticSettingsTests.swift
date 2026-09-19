// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct OpenAIAutomaticSettingsTests {
    private let endpoint = URL(string: "https://api.openai.com/v1")!

    @Test func chatHasAutomaticAbilitiesWithoutChangingPrivacyOrPermissions() throws {
        let original = OpenAIResponseSettings()
        let settings = original.forChat(endpoint: endpoint, model: "gpt-5.6-luna")
        #expect(settings.useWebSocket)
        #expect(settings.useToolSearch)
        #expect(settings.reasoningSummary)
        #expect(settings.serviceTier == "auto")
        #expect(settings.hostedTools.compactMap { $0["type"].string } == ["web_search", "code_interpreter", "image_generation"])
        #expect(!settings.store)
        #expect(!settings.useComputer)
        #expect(settings.mcpServers.isEmpty)
        #expect(original.hostedTools.isEmpty)
        try settings.validate()
    }

    @Test func legacyOffSwitchesResolveToAutomaticFeaturesInRequests() throws {
        let legacy = try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data("{\"useToolSearch\":false,\"useWebSocket\":false,\"reasoningSummary\":false,\"hostedTools\":[]}".utf8))
        let settings = legacy.forChat(endpoint: endpoint, model: "gpt-5.6-luna")
        let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings)
        let body = try client.body(state: client.restoring(nil), instructions: "", tools: [], maxTokens: 100)
        #expect(body["reasoning"]["summary"] == "auto")
        #expect(body["store"] == false)
        #expect(body["tools"].array?.count == 3)
        #expect(settings.useWebSocket && settings.useToolSearch)
    }

    @Test func preservesConfiguredToolsAndUserChoicesWithoutDuplicates() throws {
        var original = OpenAIResponseSettings()
        original.store = true
        original.useComputer = true
        original.voice.conversationVoice = "marin"
        original.hostedTools = [["type": "web_search", "search_context_size": "low"], ["type": "file_search", "vector_store_ids": ["vs_documents"]]]
        let resolved = original.forChat(endpoint: endpoint, model: "gpt-6-astra")
        #expect(resolved.store && resolved.useComputer)
        #expect(resolved.voice == original.voice)
        #expect(resolved.hostedTools.prefix(2) == original.hostedTools[...])
        #expect(resolved.forChat(endpoint: endpoint, model: "gpt-6-astra") == resolved)
        try resolved.validate()
    }

    @Test func customEndpointsAndUtilityDefaultsRemainUntouched() {
        let original = OpenAIResponseSettings()
        for url in ["https://example.com/v1", "https://api.openai.com.example.org/v1", "http://api.openai.com/v1", "https://api.openai.com/custom"] {
            #expect(original.forChat(endpoint: URL(string: url)!, model: "gpt-5.6-luna") == original)
        }
        #expect(OpenAIResponseSettings().hostedTools.isEmpty)
    }

    @Test func unknownAndSpecializedModelsDoNotInheritUnsupportedHostedTools() {
        for model in ["custom-model", "gpt-5.4-pro", "gpt-5-codex", "gpt-4.1-nano"] {
            #expect(OpenAIResponseSettings().forChat(endpoint: endpoint, model: model).hostedTools.isEmpty)
        }
    }
}
