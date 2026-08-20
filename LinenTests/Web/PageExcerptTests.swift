// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The scorer behind `lookingFor`: which slice of a long page comes back.
struct PageExcerptTests {
    private func page(burying answer: String, at position: Int = 5000, totalFiller: Int = 8000) -> String {
        let before = String(repeating: "filler prose about nothing in particular ", count: position / 41)
        let after = String(repeating: "trailing words that keep going onward ", count: (totalFiller - position) / 38)
        return before + answer + " " + after
    }

    @Test func findsTheAnswerBuriedPastTheBudget() {
        let text = page(burying: "The warranty lasts 24 months.")
        let excerpt = PageExcerpt.extract(from: text, query: "warranty", budget: 800)
        #expect(excerpt.contains("warranty lasts 24 months"))
        #expect(excerpt.count <= 810)
    }

    @Test func anEmptyQueryFallsBackToThePrefix() {
        let text = page(burying: "deep content")
        let excerpt = PageExcerpt.extract(from: text, query: "", budget: 400)
        #expect(excerpt.hasPrefix("filler prose"))
        #expect(!excerpt.contains("deep content"))
    }

    @Test func anUnmatchedQueryFallsBackToThePrefix() {
        let text = page(burying: "deep content")
        let excerpt = PageExcerpt.extract(from: text, query: "quantum chromodynamics", budget: 400)
        #expect(excerpt.hasPrefix("filler prose"))
    }

    @Test func aShortPageComesBackWhole() {
        let text = "Short page, nothing to cut."
        #expect(PageExcerpt.extract(from: text, query: "anything", budget: 400) == text)
    }

    /// Several scattered mentions, one real cluster: the window lands on the
    /// cluster, because that is where the page actually talks about it.
    @Test func picksTheDensestClusterOverAStrayMention() {
        let stray = "One passing mention of shipping here. "
        let filler = String(repeating: "unrelated words padding the page out considerably ", count: 60)
        let cluster = "Shipping costs £4. Shipping takes 3 days. Free shipping over £50."
        let text = stray + filler + cluster + " " + filler
        let excerpt = PageExcerpt.extract(from: text, query: "shipping cost", budget: 500)
        #expect(excerpt.contains("Shipping costs £4"))
    }

    @Test func matchingIsCaseInsensitive() {
        let text = page(burying: "WARRANTY: two years.")
        let excerpt = PageExcerpt.extract(from: text, query: "warranty", budget: 600)
        #expect(excerpt.contains("WARRANTY: two years."))
    }

    @Test func marksWhereThePageContinues() {
        let text = page(burying: "the answer sits here")
        let excerpt = PageExcerpt.extract(from: text, query: "answer sits", budget: 400)
        #expect(excerpt.hasPrefix("… "))
        #expect(excerpt.hasSuffix(" …"))
    }

    /// Function words match everything and would drag the window to the top
    /// of any page; only real words count.
    @Test func ignoresShortFunctionWords() {
        #expect(PageExcerpt.terms(in: "is it on the page") == ["the", "page"])
        #expect(PageExcerpt.terms(in: "warranty period?") == ["warranty", "period"])
        #expect(PageExcerpt.terms(in: "a b c") == [])
    }

    @Test func survivesDegenerateInputs() {
        #expect(PageExcerpt.extract(from: "", query: "x", budget: 100) == "")
        #expect(PageExcerpt.extract(from: "text", query: "text", budget: 0) == "")
        let long = String(repeating: "word ", count: 1000)
        _ = PageExcerpt.extract(from: long, query: String(repeating: "word ", count: 100), budget: 50)
    }
}
