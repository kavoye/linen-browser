// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct OpenAIVisualRemovalTests {
    @Test func legacyComputerPreferenceIsIgnored() throws {
        let settings = try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data(#"{"useComputer":true}"#.utf8))
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings)
        let body = try client.body(state: client.restoring(nil), instructions: "Inspect the page", tools: [], maxTokens: 100)

        #expect(body["tools"].array?.contains(where: { $0["type"] == "computer" }) == false)
        #expect(!String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("useComputer"))
    }

    @Test func unsolicitedNativeComputerCallIsRejected() throws {
        let response = OpenAITransportFixture.response([[
            "type": "computer_call", "call_id": "old-call", "status": "completed", "actions": [["type": "screenshot"]],
        ]])
        #expect(throws: OpenAIFailure.self) { try OpenAIModelStep.output(response) }
    }
}
