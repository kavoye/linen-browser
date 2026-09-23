// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

private actor OpenAISocketFixture: OpenAISocketConnection {
    var sent: [OpenAIJSON] = []
    var closed = false
    var queue: [OpenAIJSON]
    init(_ queue: [OpenAIJSON]) {
        self.queue = queue
    }
    func send(_ event: OpenAIJSON) {
        sent.append(event)
    }
    func receive() throws -> OpenAIJSON {
        guard !queue.isEmpty else { throw OpenAIFailure(kind: .streamInterrupted) }
        return queue.removeFirst()
    }
    func close() {
        closed = true
    }
}

@MainActor
struct OpenAICompatibilityTests {
    @Test func discardedHistoryClosesCachedProviderConnections() async throws {
        let response = OpenAITransportFixture.response([OpenAITransportFixture.message("Private answer")])
        let socket = OpenAISocketFixture([["type": "response.completed", "response": response]])
        let pool = OpenAIResponseSocketPool { socket }
        try await pool.generate(["input": [["role": "user", "content": "Private prompt"]]]) { _ in }
        await pool.discardHistory(cancelActive: false)
        #expect(await socket.closed)
    }

    @Test func everyBuiltInToolHasCompleteStrictSchemaDefinitions() throws {
        let log = ConversationLog(database: .temporary())
        let toolkit = AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log)
        for tool in makeAgentTools(toolkit: toolkit) + [UpdateProgressTool()] {
            let schema = try OpenAISchema.strict(tool.parameters, dependencies: OpenAISchema.browserDependencies)
            #expect(schema["type"] == "object", "\(tool.name)")
            #expect(schema["additionalProperties"] == false, "\(tool.name)")
            #expect(OpenAISchema.references(in: schema).isSubset(of: Set(schema["$defs"].object?.keys ?? [:].keys)), "\(tool.name)")
        }
    }

    @Test func nestedStructuredSchemasKeepReferencesAtTheDocumentRoot() throws {
        let schema = try OpenAISchema.wrappedValue([HarnessTool.Arguments].self)
        let definitions = try #require(schema["$defs"].object)
        #expect(!definitions.isEmpty)
        #expect(schema["properties"]["value"]["$defs"] == .null)
        func checkReferences(_ value: OpenAIJSON) {
            if let reference = value["$ref"].string, reference.hasPrefix("#/$defs/") {
                #expect(definitions[String(reference.dropFirst(8))] != nil)
            }
            for child in value.object?.values ?? [:].values {
                checkReferences(child)
            }
            for child in value.array ?? [] {
                checkReferences(child)
            }
        }
        checkReferences(schema)
    }

    @Test func websocketSendsOnlyNewInputAfterACompletedResponse() async throws {
        let first = OpenAITransportFixture.response([OpenAITransportFixture.reasoning, OpenAITransportFixture.call])
        let second = OpenAITransportFixture.response([OpenAITransportFixture.message("Done")])
        let socket = OpenAISocketFixture([
            ["type": "response.future", "new": true], ["type": "response.completed", "response": first],
            ["type": "response.completed", "response": second],
        ])
        let pool = OpenAIResponseSocketPool { socket }
        let initial: [OpenAIJSON] = [["role": "user", "content": "Read this page"]]
        try await pool.generate(["model": "fixture", "input": .array(initial), "stream": true, "store": false]) { _ in }
        let result: OpenAIJSON = ["type": "function_call_output", "call_id": "call_read", "output": "Verified"]
        let continuation = initial + (first["output"].array ?? []) + [result]
        try await pool.generate(["model": "fixture", "input": .array(continuation), "stream": true, "store": false]) { _ in }
        let sent = await socket.sent
        #expect(sent.count == 2)
        #expect(sent[0]["type"] == "response.create")
        #expect(sent[0]["stream"] == .null)
        #expect(sent[1]["input"] == .array([result]))
        #expect(sent[1]["previous_response_id"] == first["id"])
        #expect(sent[1]["store"] == false)
        #expect(await socket.closed == false)
    }

    @Test func websocketDoesNotReplayFailedRequests() async throws {
        let socket = OpenAISocketFixture([["type": "error", "error": ["code": "server_error"]]])
        let pool = OpenAIResponseSocketPool { socket }
        await #expect(throws: OpenAIFailure.self) { try await pool.generate(["input": []]) { _ in } }
        #expect(await socket.sent.count == 1)
        #expect(await socket.closed)
    }

    @Test(arguments: ["server_error", "previous_response_not_found", "websocket_connection_limit_reached", "context_length_exceeded"])
    func websocketPreservesFailureMetadata(code: String) async throws {
        let socket = OpenAISocketFixture([["type": "error", "status": 400, "error": ["code": .string(code)]]])
        let pool = OpenAIResponseSocketPool { socket }
        do {
            try await pool.generate(["input": []]) { _ in }
            Issue.record("Expected the provider error")
        } catch let failure as OpenAIFailure {
            #expect(failure.code == code)
            #expect(failure.status == 400)
            #expect(failure.kind == (code == "context_length_exceeded" ? .contextLimit : .http))
        }
        #expect(await socket.sent.count == 1)
        #expect(await socket.closed)
    }

    @Test func modelOptionsAndNewFieldsReachTheNativeRequest() throws {
        var settings = OpenAIResponseSettings()
        settings.reasoningEffort = "max"
        settings.additionalParameters = [
            "reasoning": ["mode": "pro", "future_option": true],
            "context_management": [["type": "compaction", "compact_threshold": 120_000]],
            "prompt_cache_options": ["future_option": 3],
        ]
        let client = OpenAIResponsesClient(
            endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-6-astra", settings: settings)
        let body = try client.body(state: client.restoring(nil), instructions: "Rules", tools: [], maxTokens: 48_000)
        #expect(body["reasoning"]["effort"] == "max")
        #expect(body["reasoning"]["mode"] == "pro")
        #expect(body["context_management"] == settings.additionalParameters["context_management"])
        #expect(body["prompt_cache_options"] == settings.additionalParameters["prompt_cache_options"])
        #expect(body["include"].array?.contains("reasoning.encrypted_content") == true)
        #expect(ReasoningCatalog.efforts(for: ProviderCatalog.openAI, model: "gpt-6-astra") == [.low, .medium, .high, .xhigh, .max])
        let old = OpenAIResponsesClient(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-4.1")
        let oldBody = try old.body(state: old.restoring(nil), instructions: "", tools: [], maxTokens: 500)
        #expect(oldBody["reasoning"] == .null)
        #expect(oldBody["text"]["verbosity"] == .null)
    }

    @Test func managedFieldsAreRejectedInsteadOfSilentlyOverridden() throws {
        var settings = OpenAIResponseSettings()
        settings.additionalParameters = ["input": "Replace the task", "future_field": true]
        #expect(throws: OpenAISettingsError.self) { try settings.validate() }
        let restored = try JSONDecoder().decode(OpenAIResponseSettings.self, from: Data("{\"verbosity\":\"high\"}".utf8))
        #expect(restored.verbosity == "high")
        #expect(restored.store == false)
        #expect(restored.useWebSocket == false)
    }

    @Test func utilityStringsAndStructuredResultsUseNativeResponses() async throws {
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAITransportFixture.message("A title")]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("{\"value\":[\"One\",\"Two\"]}")]),
        ])
        let client = OpenAIResponsesClient(
            endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-6-astra", transport: wire)
        let model = OpenAIUtilityModel(client: client, maxTokens: 500)
        let session = LanguageModelSession(model: model, instructions: "Name this page")
        #expect(try await session.respond(to: "Page").content == "A title")
        let structured = LanguageModelSession(model: model)
        #expect(try await structured.respond(to: "Two names", generating: [String].self).content == ["One", "Two"])
        let first = try OpenAIJSON.decode(wire.requests[0].body!)
        #expect(first["input"].array?.count == 1)
        let second = try OpenAIJSON.decode(wire.requests[1].body!)
        #expect(second["text"]["format"]["schema"]["type"] == "object")
        #expect(second["tools"] == [])
    }

    @Test func visibleOutputExcludesEncryptedReasoningAndUnsafeLinks() throws {
        var output = OpenAIPresentation()
        output.append(
            OpenAITransportFixture.response([
                [
                    "type": "reasoning", "encrypted_content": "DO-NOT-DISPLAY",
                    "summary": [["type": "summary_text", "text": "Checked the sources."]],
                ],
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text", "text": "Answer",
                            "annotations": [
                                ["type": "url_citation", "url": "https://example.test/source", "title": "Source"],
                                ["type": "url_citation", "url": "javascript:alert(1)", "title": "Unsafe"],
                                [
                                    "type": "container_file_citation", "container_id": "cntr_fixture", "file_id": "file_fixture",
                                    "filename": "result.csv",
                                ],
                            ],
                        ],
                    ],
                ],
                [
                    "type": "image_generation_call", "id": "image_fixture", "result": .string(Data([1, 2, 3]).base64EncodedString()),
                    "output_format": "png",
                ],
            ]))
        #expect(output.sources.count == 1)
        #expect(output.files.first?.containerID == "cntr_fixture")
        #expect(output.pictures.first?.data == Data([1, 2, 3]))
        #expect(output.summaries == ["Checked the sources."])
        #expect(!String(decoding: try JSONEncoder().encode(output), as: UTF8.self).contains("DO-NOT-DISPLAY"))
    }

    @Test func resourcesPreserveUnknownFieldsAndCursorPagination() async throws {
        let wire = OpenAITransportFixture([
            ["id": "resp_background", "status": "queued", "future": true],
            ["has_more": true, "data": [["id": "file_1", "future": 3]]],
            ["has_more": false, "data": [["id": "file_2"]]],
        ])
        let api = OpenAIAPI(transport: wire)
        #expect(try await api.createBackgroundResponse(["model": "fixture", "new_parameter": true])["future"] == true)
        var pages: [OpenAIJSON] = []
        for try await page in api.pages(["files"]) {
            pages.append(page)
        }
        #expect(pages.count == 2)
        #expect(pages.first?["data"].array?.first?["future"] == 3)
        #expect(wire.requests[2].query["after"] == "file_1")
        let background = try OpenAIJSON.decode(wire.requests[0].body!)
        #expect(background["background"] == true)
        #expect(background["new_parameter"] == true)
    }

    @Test func uploadsAndEndpointBoundariesAreChecked() async throws {
        let wire = OpenAITransportFixture([["id": "file_fixture"]])
        _ = try await OpenAIAPI(transport: wire).upload(
            ["audio", "transcriptions"], fields: ["model": "fixture"],
            files: [.init(field: "file", filename: "audio.wav", mimeType: "audio/wav", data: Data([0, 1, 2]))])
        #expect(wire.requests.first?.contentType.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(wire.requests.first?.body?.contains(Data([0, 1, 2])) == true)
        let transport = OpenAIHTTPTransport(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture")
        for path in [["..", "files"], ["%2e%2e", "files"], ["files", "a/b"], ["files", "\\evil"]] {
            #expect(throws: OpenAIFailure.self) { try transport.urlRequest(.init(path: path)) }
        }
        let request = try transport.urlRequest(.init(path: ["files", "file_1", "content"], method: "GET"))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/files/file_1/content")
    }

    @Test func citedDownloadsUseTheCorrectResource() async throws {
        let wire = OpenAITransportFixture([[:], [:]])
        let api = OpenAIAPI(transport: wire)
        _ = try await api.download(.init(fileID: "cfile_fixture", containerID: "cntr_fixture", name: "result.csv"))
        _ = try await api.download(.init(fileID: "file_fixture", containerID: nil, name: "source.txt"))
        #expect(wire.requests.map(\.path) == [
            ["containers", "cntr_fixture", "files", "cfile_fixture", "content"], ["files", "file_fixture", "content"],
        ])
        #expect(wire.requests.allSatisfy { $0.method == "GET" })
    }
}
