// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.serialized, .boundedWebViews)
struct OpenAIComputerWorkflowTests {
    @Test func productionExecutorReturnsScreenshotsAndExecutesOnce() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        let (frame, _) = try await PageDriver.computerFrame(in: fixture.tab.webView)
        let click: OpenAIJSON = ["type": "click", "button": "left", "x": .number(60 * frame.pixels.width / frame.geometry.width),
                                "y": .number(110 * frame.pixels.height / frame.geometry.height), ]
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAIComputerTests.call()]),
            OpenAITransportFixture.response([OpenAIComputerTests.call([click], id: "computer_2")]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Verified.")]),
        ])
        var settings = OpenAIResponseSettings()
        settings.useComputer = true
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings, transport: wire)
        await fixture.run(client: client, prompt: "Click Choose once.")
        #expect(try await fixture.tab.webView.evaluateJavaScript("window.chosen || 0") as? Int == 1)
        #expect(fixture.completed)
        let third = try OpenAIJSON.decode(wire.requests[2].body!)
        #expect(third["input"].array?.filter { $0["type"] == "computer_call_output" }.count == 2)
        #expect(third["tools"].array?.contains(where: { $0["name"].string == OpenAIComputerCall.toolName }) == false)
        #expect(fixture.log.checkpoint(forTab: fixture.tab.id)?.openAI?.computerCallIDs == ["computer_1", "computer_2"])
    }

    @Test func unavailableSafetyApprovalStopsTheTaskWithoutClicking() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        var call = OpenAIComputerTests.call()
        call["pending_safety_checks"] = [["id": "safety_1", "code": "confirmation", "message": "Confirm before continuing."]]
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([call]), OpenAITransportFixture.response([OpenAITransportFixture.message("Waiting for approval.")])])
        var settings = OpenAIResponseSettings()
        settings.useComputer = true
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings, transport: wire)
        await fixture.run(client: client, prompt: "Inspect this page.")
        #expect(try await fixture.tab.webView.evaluateJavaScript("window.chosen || 0") as? Int == 0)
        #expect(!fixture.completed)
        #expect(wire.requests.count == 2)
        let summary = try OpenAIJSON.decode(wire.requests[1].body!)
        #expect(summary["tools"].array?.contains(["type": "computer"]) == false)
        #expect(summary["input"].array?.contains(where: { $0["type"] == "computer_call" }) == false)
    }

    @Test func sameOriginNavigationReturnsANewScreenshot() async throws {
        let fixture = try await ComputerWorkflowFixture()
        defer { fixture.close() }
        _ = try await fixture.tab.webView.evaluateJavaScript("document.querySelector('button').onclick=()=>{location.hash='chosen'}; true")
        let (frame, _) = try await PageDriver.computerFrame(in: fixture.tab.webView)
        let click: OpenAIJSON = ["type": "click", "button": "left", "x": .number(60 * frame.pixels.width / frame.geometry.width),
                                "y": .number(110 * frame.pixels.height / frame.geometry.height), ]
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAIComputerTests.call()]),
            OpenAITransportFixture.response([OpenAIComputerTests.call([click], id: "computer_2")]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Verified.")]),
        ])
        var settings = OpenAIResponseSettings()
        settings.useComputer = true
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-5.6-luna", settings: settings, transport: wire)
        await fixture.run(client: client, prompt: "Click Choose once.")
        #expect(fixture.tab.webView.url?.fragment == "chosen")
        let request = try OpenAIJSON.decode(try #require(wire.requests.last?.body))
        #expect(request["input"].array?.filter { $0["type"] == "computer_call_output" }.count == 2)
    }
}
