// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct PageWatchJudgeTests {
    private final class SmallWindowModel: LanguageModel, @unchecked Sendable {
        private let lock = NSLock()
        private let window: Int
        private let failure: any Error
        private var lengths: [Int] = []

        init(window: Int, failure: any Error = LanguageModelSession.GenerationError.exceededContextWindowSize(
            .init(debugDescription: "fixture")
        )) {
            self.window = window
            self.failure = failure
        }

        var promptLengths: [Int] {
            lock.withLock { lengths }
        }

        func respond<Content>(
            within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
            includeSchemaInPrompt: Bool, options: GenerationOptions
        ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
            let length = prompt.description.count
            lock.withLock { lengths.append(length) }
            guard length <= window else { throw failure }
            let json = #"{"state":"$42.99","met":true,"message":"The price dropped to $42.99."}"#
            let raw = try GeneratedContent(json: json)
            return .init(content: try Content(raw), rawContent: raw, transcriptEntries: [][...])
        }

        func streamResponse<Content>(
            within session: LanguageModelSession, to prompt: Prompt, generating type: Content.Type,
            includeSchemaInPrompt: Bool, options: GenerationOptions
        ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
            fatalError("The judge never streams")
        }
    }

    private let watch = PageWatch(
        id: UUID(),
        url: URL(string: "https://shop.example/kettle")!,
        title: "Kettle",
        condition: "price below $50",
        interval: 3600,
        created: Date(timeIntervalSinceReferenceDate: 800_000_000),
        nextCheck: .distantFuture
    )

    private func reading(characters: Int) -> PageWatchReading {
        PageWatchReading(title: "Kettle", text: String(repeating: "Kettle $42.99 In stock. ", count: characters / 24))
    }

    @Test func aPageTooLongForTheModelIsHalvedUntilItFits() async throws {
        let model = SmallWindowModel(window: 3_000)

        let verdict = await PageWatchJudge.judge(watch, reading: reading(characters: 12_000), model: model)

        #expect(verdict?.met == true)
        #expect(verdict?.message == "The price dropped to $42.99.")
        let lengths = model.promptLengths
        #expect(lengths.count >= 3, "the page is cut more than once")
        #expect(zip(lengths, lengths.dropFirst()).allSatisfy { $0 > $1 }, "each try sends less text")
        #expect((lengths.last ?? .max) <= 3_000)
    }

    @Test func aPageThatNeverFitsGivesUpAtFiveHundredCharacters() async {
        let model = SmallWindowModel(window: 10)

        let verdict = await PageWatchJudge.judge(watch, reading: reading(characters: 4_000), model: model)

        #expect(verdict == nil)
        #expect(model.promptLengths.count == 4, "4,000 halves to 2,000, 1,000 and 500, then stops")
    }

    @Test func anotherModelErrorIsNotRetried() async {
        let model = SmallWindowModel(window: 0, failure: CancellationError())

        let verdict = await PageWatchJudge.judge(watch, reading: reading(characters: 4_000), model: model)

        #expect(verdict == nil)
        #expect(model.promptLengths.count == 1)
    }
}
