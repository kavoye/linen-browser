// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIFileTests {
    private var pdf: AssistantAttachment {
        .init(id: UUID(), name: "document.pdf", contentType: "com.adobe.pdf", data: Data("%PDF fixture".utf8),
            text: "Extracted document text", images: [.init(data: Data([1, 2, 3]), mimeType: "image/jpeg")])
    }
    private func client(_ wire: OpenAITransportFixture) -> OpenAIResponsesClient {
        .init(endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture", model: "gpt-5.6-luna", transport: wire)
    }

    @Test func nativePDFReplacesRenderedPagesButPreservesGenericHistoryAndCheckpointReplay() async throws {
        let wire = OpenAITransportFixture([
            OpenAITransportFixture.response([OpenAITransportFixture.call]),
            OpenAITransportFixture.response([OpenAITransportFixture.message("Read the document")]),
        ])
        let fixture = HarnessFixture([], openAI: client(wire))
        await fixture.run("Read this file", attachments: [pdf])
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .completed)
        #expect(wire.requests.count == 2)
        for request in wire.requests {
            let body = try OpenAIJSON.decode(#require(request.body))
            let content = try #require(body["input"].array?.first?["content"].array)
            #expect(content.filter { $0["type"] == "input_file" }.count == 1)
            #expect(!content.contains { $0["type"] == "input_image" })
            #expect(!content.contains { $0["text"].string?.contains("Extracted document text") == true })
        }
        let checkpoint = try #require(fixture.log.checkpoint(forTab: fixture.tabID))
        #expect(HarnessFixture.flattened(checkpoint.transcript).contains("Extracted document text"))
        let state = try #require(checkpoint.openAI)
        let restored = try JSONDecoder().decode(OpenAIConversationState.self, from: JSONEncoder().encode(state))
        #expect(try restored.synchronizing(checkpoint.transcript).items == state.items)
    }

    @Test func failedNativeRequestKeepsItsFileForResume() async throws {
        let wire = OpenAITransportFixture([OpenAITransportFixture.response([], status: "failed")])
        let fixture = HarnessFixture([], openAI: client(wire))
        await fixture.run("Read this file", attachments: [pdf])
        let state = try #require(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI)
        let content = try #require(state.items.first?["content"].array)
        #expect(content.contains { $0["type"] == "input_file" })
        #expect(!content.contains { $0["type"] == "input_image" })
    }

    @Test func textOnlyAndOtherProvidersKeepExistingAttachmentBehavior() async throws {
        #expect(try OpenAIAttachmentInput.make(prompt: "Read", attachments: [pdf], textOnly: true) == nil)
        let fixture = HarnessFixture([.text("Read")])
        await fixture.run("Read this file", attachments: [pdf])
        #expect(fixture.model.requests.first?.contains("Extracted document text") == true)
        #expect(fixture.log.checkpoint(forTab: fixture.tabID)?.openAI == nil)
    }

    @Test func csvRetainsRowsBeyondNativeSpreadsheetAugmentationLimit() throws {
        let text = "value\n" + (0..<1_100).map(String.init).joined(separator: "\n")
        let file = try AttachmentImporter.prepare(data: Data(text.utf8), name: "rows.csv")
        let content = try #require(try OpenAIAttachmentInput.make(prompt: "Read", attachments: [file], textOnly: false)?.content)
        #expect(!content.contains { $0["type"] == "input_file" })
        #expect(content.contains { $0["text"].string?.contains("1099") == true })
    }

    @Test func fileContentCannotReplaceAnAlreadyAnchoredPrompt() throws {
        let transcript = Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Prompt"))]))])
        let anchored = try OpenAIConversationState(binding: "fixture").synchronizing(transcript)
        let input = try #require(try OpenAIAttachmentInput.make(prompt: "Replace", attachments: [pdf], textOnly: false))
        #expect(throws: OpenAIFailure.self) { try anchored.synchronizing(transcript, attachmentInput: input) }
    }

    @Test func collectionUploadsBatchPollsAndDeletesOwnedResources() async throws {
        let wire = OpenAITransportFixture([
            ["id": "vs_fixture"], ["id": "file_first"], ["id": "file_second"],
            ["id": "batch_fixture", "status": "in_progress"],
            ["id": "batch_fixture", "status": "completed", "file_counts": ["completed": 2, "failed": 0, "cancelled": 0]],
            [:], [:], [:],
        ])
        let library = OpenAIFileLibrary(api: .init(transport: wire), pollInterval: .zero, maximumPolls: 2)
        var changes: [OpenAIFileCollection] = []
        let file = OpenAIUpload(field: "file", filename: "notes.txt", mimeType: "text/plain", data: Data("Notes".utf8))
        let collection = try await library.create(name: "Notes", files: [file, file]) { changes.append($0) }
        #expect(collection.ready)
        #expect(changes.map(\.fileIDs.count) == [0, 1, 2, 2])
        #expect(changes.dropLast().allSatisfy { !$0.ready })
        let batch = try OpenAIJSON.decode(#require(wire.requests[3].body))
        #expect(batch["file_ids"] == ["file_first", "file_second"])
        try await library.remove(collection) { changes.append($0) }
        #expect(wire.requests.suffix(3).map(\.path) == [
            ["vector_stores", "vs_fixture"], ["files", "file_first"], ["files", "file_second"],
        ])
        #expect(changes.last?.fileIDs.isEmpty == true)
        #expect(changes.last?.storeDeleted == true)
    }

    @Test func indexingFailureNeverEnablesTheCollectionAndRetainsCleanupIDs() async throws {
        let wire = OpenAITransportFixture([
            ["id": "vs_fixture"], ["id": "file_fixture"],
            ["id": "batch_fixture", "status": "completed", "file_counts": ["completed": 0, "failed": 1, "cancelled": 0]],
        ])
        var pending: OpenAIFileCollection?
        let file = OpenAIUpload(field: "file", filename: "notes.txt", mimeType: "text/plain", data: Data("Notes".utf8))
        await #expect(throws: OpenAIFileLibraryFailure.indexing) {
            _ = try await OpenAIFileLibrary(api: .init(transport: wire)).create(name: "Notes", files: [file]) { pending = $0 }
        }
        #expect(pending?.ready == false)
        #expect(pending?.fileIDs == ["file_fixture"])
    }

    @Test func cancellationAfterUploadDoesNotStartIndexing() async {
        let wire = OpenAITransportFixture([["id": "vs_fixture"], ["id": "file_fixture"]])
        let library = OpenAIFileLibrary(api: .init(transport: wire))
        let file = OpenAIUpload(field: "file", filename: "notes.txt", mimeType: "text/plain", data: Data("Notes".utf8))
        let task = Task {
            try await library.create(name: "Notes", files: [file]) { collection in
                if !collection.fileIDs.isEmpty {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(wire.requests.map(\.path) == [["vector_stores"], ["files"]])
    }

    @Test func partialCleanupCanResumeWithoutDeletingCompletedResourcesAgain() async throws {
        let wire = OpenAITransportFixture([[:], [:]])
        let library = OpenAIFileLibrary(api: .init(transport: wire))
        let original = OpenAIFileCollection(id: "vs_fixture", name: "Notes", fileIDs: ["file_first", "file_second"], createdAt: .now)
        var pending = original
        await #expect(throws: OpenAIFailure.self) { try await library.remove(original) { pending = $0 } }
        #expect(pending.storeDeleted)
        #expect(pending.fileIDs == ["file_second"])
        let retry = OpenAITransportFixture([[:]])
        try await OpenAIFileLibrary(api: .init(transport: retry)).remove(pending) { _ in }
        #expect(retry.requests.map(\.path) == [["files", "file_second"]])
    }

    @Test func selectingCollectionsPreservesOtherToolsAndSearchParameters() {
        let tools: [OpenAIJSON] = [["type": "web_search"], [
            "type": "file_search", "vector_store_ids": ["vs_existing"], "max_num_results": 3, "filters": ["future": true],
        ], ]
        let selected = OpenAIFileLibrary.select("vs_new", enabled: true, tools: tools)
        #expect(selected[1]["vector_store_ids"] == ["vs_existing", "vs_new"])
        #expect(selected[1]["max_num_results"] == 3)
        #expect(OpenAIFileLibrary.select("vs_new", enabled: false, tools: selected) == tools)
    }

    @Test func expiredCollectionsFailBeforeSendingARequestAndCanBeDisabled() throws {
        let now = Date()
        let expired = OpenAIFileCollection(id: "vs_expired", name: "Notes", ready: true, createdAt: now.addingTimeInterval(-604_800))
        let tools = OpenAIFileLibrary.select(expired.id, enabled: true, tools: [])
        #expect(throws: OpenAIFileLibraryFailure.unavailableCollection) {
            try OpenAIFileLibrary.validateSelection(tools: tools, collections: [expired], now: now)
        }
        try OpenAIFileLibrary.validateSelection(tools: OpenAIFileLibrary.select(expired.id, enabled: false, tools: tools),
            collections: [expired], now: now)
        #expect(!expired.isAvailable(at: now))
    }

    @Test func expiredCollectionShowsAnActionableErrorWithoutGeneratingAPauseSummary() async {
        let wire = OpenAITransportFixture([])
        var client = client(wire)
        let expired = OpenAIFileCollection(id: "vs_" + UUID().uuidString, name: "Notes", ready: true,
            createdAt: Date().addingTimeInterval(-604_801))
        OpenAIFileCollectionStore.update(expired, binding: client.fileLibraryBinding)
        defer { OpenAIFileCollectionStore.remove(expired.id, binding: client.fileLibraryBinding) }
        client.settings.hostedTools = OpenAIFileLibrary.select(expired.id, enabled: true, tools: [])
        let fixture = HarnessFixture([], openAI: client)
        await fixture.run("Search my collection")
        #expect(wire.requests.isEmpty)
        #expect(fixture.reply.text?.contains("Use in chat") == true)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state != .completed)
    }
}
