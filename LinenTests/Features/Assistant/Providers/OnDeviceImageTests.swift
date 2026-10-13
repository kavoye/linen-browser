// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OnDeviceImageTests {
    @Test func onDeviceModelReadsAttachedImagesWhenTheSystemModelHasVision() {
        let accepts = ModelImageSupport.acceptsImages(for: ProviderCatalog.appleOnDevice, model: "")
        #expect(accepts == SystemLanguageModel.default.supportsImageInput)
    }

    @Test func onDeviceModelGetsAttachmentsButNeverScreenshotTools() {
        let onDevice = agent(model: SystemLanguageModel.default)
        let hosted = agent(model: HarnessScript([]))

        #expect(onDevice.acceptsImages)
        #expect(!onDevice.seesScreenshots)
        #expect(Set(onDevice.makeSession().tools.map(\.name)).isDisjoint(with: AgentToolCatalog.visualToolIDs))
        #expect(hosted.seesScreenshots)
        #expect(!Set(hosted.makeSession().tools.map(\.name)).isDisjoint(with: AgentToolCatalog.visualToolIDs))
    }

    @Test func restoredToolOutputsDropScreenshotsButPromptsKeepAttachments() {
        let image = Transcript.ImageSegment(data: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg")
        let transcript = Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: "What is this?")), .image(image)])),
            .toolOutput(.init(id: "call", toolName: "screenshot", segments: [
                .text(.init(content: "Page")), .image(image),
            ])),
        ])

        let entries = Array(ModelImageSupport.withoutToolImages(transcript))

        guard case .prompt(let prompt) = entries[0], case .toolOutput(let output) = entries[1] else {
            Issue.record("Entries changed kind")
            return
        }
        #expect(prompt.segments.count == 2)
        #expect(output.segments.count == 1)
    }

    private func agent(model: any LanguageModel) -> AnyLanguageModelAgent {
        let log = ConversationLog(database: .temporary())
        return AnyLanguageModelAgent(
            name: "fixture", modelID: "fixture", model: model, options: GenerationOptions(),
            budget: ContextBudget(windowTokens: 128_000, responseTokens: 2_000, inputTokens: 100_000, toolSchemaTokens: 0,
                                  instructionTier: .compact, toolTier: .full, toolOutput: .standard, retainedExchanges: 12, retainedToolRounds: 1),
            acceptsImages: true,
            enabledToolIDs: AgentToolCatalog.visualToolIDs,
            toolkit: AgentToolkit(browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: log),
            log: log
        )
    }
}
