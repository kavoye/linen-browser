// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct AutomaticAttachmentTests {
    @Test func unsupportedImagesRetryAsTextAndStayTextOnlyForLaterTurns() async throws {
        let rejection = NSError(domain: "fixture", code: 400, userInfo: [
            NSLocalizedDescriptionKey: "This model does not support image inputs",
        ])
        let fixture = HarnessFixture([.failure(rejection), .calls(["readPage"]), .text("Read the invoice.")])
        await fixture.run("Read this", attachments: [file()])
        #expect(fixture.model.transcripts.map(ModelImageSupport.containsImages) == [true, false, false])
        #expect(fixture.state.calls == 1)
        #expect(fixture.model.requests[1].contains("Invoice total 42"))
        #expect(fixture.reply.text == "Read the invoice.")
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.attachmentTextOnly == true)

        await fixture.run("Read another", attachments: [file()])
        #expect(fixture.model.transcripts.last.map(ModelImageSupport.containsImages) == false)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.attachmentTextOnly == true)
        let checkpoint = try #require(fixture.log.checkpoint(forTab: fixture.tabID))
        #expect(!ModelImageSupport.containsImages(checkpoint.transcript))
    }

    @Test func missingOCRAsksForAnImageCapableModel() async {
        let rejection = NSError(domain: "fixture", code: 400, userInfo: [
            NSLocalizedDescriptionKey: "Image input is not supported by this model",
        ])
        let fixture = HarnessFixture([.failure(rejection)])
        await fixture.run("Describe this", attachments: [file(text: "")])
        #expect(fixture.model.requests.count == 1)
        #expect(fixture.reply.text?.contains("Choose a model that can read images") == true)
        #expect(fixture.reply.text?.contains("Extract Text Only") == false)
    }

    @Test func readsExplicitModelCapabilitiesWithoutGuessingFromTheName() {
        #expect(ModelImageSupport.declaredSupport(in: ["architecture": ["input_modalities": ["text", "image"]]]) == true)
        #expect(ModelImageSupport.declaredSupport(in: ["architecture": ["input_modalities": ["text"]]]) == false)
        #expect(ModelImageSupport.declaredSupport(in: ["capabilities": ["vision": false]]) == false)
        #expect(ModelImageSupport.declaredSupport(in: ["id": "some-new-model"]) == nil)
    }

    @Test(arguments: [
        ("This model does not support image inputs", true),
        ("image_url content is not supported by this model", true),
        ("This is not a vision model", true),
        ("Unsupported image format", false),
        ("Invalid image URL", false),
        ("Invalid API key", false),
        ("Image size too large", false),
    ])
    func onlyCapabilityFailuresTriggerFallback(message: String, expected: Bool) {
        let error = NSError(domain: "fixture", code: 400, userInfo: [NSLocalizedDescriptionKey: message])
        #expect(ModelImageSupport.isImageRejection(error) == expected)
    }

    private func file(text: String = "Invoice total 42") -> AssistantAttachment {
        AssistantAttachment(
            id: UUID(), name: "invoice.png", contentType: "public.png", data: Data([1]),
            text: text, images: [.init(data: Data([1]), mimeType: "image/png")]
        )
    }
}
