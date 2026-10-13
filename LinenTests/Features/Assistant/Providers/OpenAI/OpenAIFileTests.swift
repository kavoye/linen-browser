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

}
