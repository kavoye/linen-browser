// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAILiveRecorderTests {
    @Test func failedHostedArtifactValidationStillDeletesItsContainer() async throws {
        let wire = OpenAITransportFixture([
            ["id": "cntr_fixture"], OpenAITransportFixture.response([OpenAITransportFixture.message("323")]), [:],
        ])
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "fixture", model: "validation-model", transport: wire)
        await #expect(throws: OpenAIHostedLiveFailure.fileCitation) {
            _ = try await OpenAIHostedLiveChecks.codeInterpreter(client)
        }
        #expect(wire.requests.last?.path == ["containers", "cntr_fixture"])
        #expect(wire.requests.last?.method == "DELETE")
        #expect(wire.requests.count == 3)
    }

    @Test func nonemptyImageBytesDoNotEstablishSuccessfulGeneration() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([
            ["type": "image_generation_call", "id": "img_fixture", "status": "completed", "result": "AQID"],
        ]), ])
        let client = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!,
            apiKey: "fixture", model: "validation-model", transport: wire)
        await #expect(throws: OpenAIHostedLiveFailure.imageDecode) {
            _ = try await OpenAIHostedLiveChecks.imageGeneration(client)
        }
        #expect(wire.requests.count == 1)
    }

    @Test func evidenceKeepsUsageButExcludesProviderContent() async throws {
        let response = OpenAITransportFixture.response([
            OpenAITransportFixture.reasoning, OpenAITransportFixture.message("PRIVATE_VISIBLE_TEXT"),
        ])
        let recorder = OpenAILiveRecorder(requestLimit: 1)
        recorder.select("redaction")
        let transport = OpenAILiveTransport(base: OpenAITransportFixture([response]), recorder: recorder)
        _ = try await OpenAIAPI(transport: transport).createResponse(["input": "PRIVATE_PROMPT"]) { _ in }
        let snapshot = recorder.snapshot
        #expect(snapshot.count == 1)
        #expect(snapshot[0]["usage"]["input_tokens"] == "100")
        #expect(snapshot[0]["first_text_ms"].int != nil)
        let encoded = try OpenAIJSON.array(snapshot).text()
        #expect(!encoded.contains("opaque-private-state"))
        #expect(!encoded.contains("PRIVATE_VISIBLE_TEXT"))
        #expect(!encoded.contains("PRIVATE_PROMPT"))
        await #expect(throws: OpenAILiveFailure.requestLimit) {
            _ = try await OpenAIAPI(transport: transport).request(["responses"], body: [:])
        }
    }

    @Test func interruptedStreamsAreRecordedAsFailures() async {
        let recorder = OpenAILiveRecorder()
        let transport = OpenAILiveTransport(base: OpenAITransportFixture([]), recorder: recorder)
        await #expect(throws: OpenAIFailure.self) {
            _ = try await OpenAIAPI(transport: transport).createResponse([:]) { _ in }
        }
        #expect(recorder.snapshot.count == 2)
        #expect(recorder.snapshot.allSatisfy { $0["status"] == "failed" })
        #expect(recorder.snapshot.allSatisfy { $0["error"] == "streamInterrupted" })
    }
}
