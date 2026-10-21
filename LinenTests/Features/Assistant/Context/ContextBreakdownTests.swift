// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct ContextBreakdownTests {
    @Test func transcriptSplitsIntoCategories() {
        let budget = ContextBudget.resolve(windowTokens: 16_384, desiredResponseTokens: 2_048, measuredSchemaTokens: 900)
        let transcript = Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: String(repeating: "a", count: 400)))])),
            .response(.init(assetIDs: [], segments: [.text(.init(content: String(repeating: "b", count: 200)))])),
            .toolOutput(.init(id: "1", toolName: "readPage", segments: [.text(.init(content: String(repeating: "c", count: 300)))])),
        ])
        let breakdown = TranscriptMetrics.contextBreakdown(in: transcript, budget: budget)
        #expect(breakdown.tokens[.messages] == 150)
        #expect(breakdown.tokens[.toolActivity] == 100)
        #expect(breakdown.tokens[.availableTools] == 900)
        #expect(breakdown.tokens[.reasoning] == nil)
        #expect(breakdown.reservedTokens == budget.windowTokens - budget.inputTokens)
    }

    @Test func scalingMatchesTheReportedTotalAndDropsEmptyRows() {
        let breakdown = ContextBreakdown(tokens: [.messages: 300, .availableTools: 100, .images: 0])
        let rows = breakdown.scaled(to: 800)
        #expect(rows.map(\.category) == [.messages, .availableTools])
        #expect(rows.map(\.tokens) == [600, 200])
        #expect(ContextBreakdown().scaled(to: 800).isEmpty)
    }
}
