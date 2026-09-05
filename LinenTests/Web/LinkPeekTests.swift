// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

struct LinkPeekTests {
    @Test func onlyWebAddressesArePeekedAt() {
        #expect(LinkPeekLoader.canPeek(URL(string: "https://example.com/post")!))
        #expect(LinkPeekLoader.canPeek(URL(string: "http://example.com")!))
        #expect(!LinkPeekLoader.canPeek(URL(string: "mailto:someone@example.com")!))
        #expect(!LinkPeekLoader.canPeek(URL(string: "javascript:alert(1)")!))
        #expect(!LinkPeekLoader.canPeek(URL(string: "file:///Users/someone/notes.html")!))
        #expect(!LinkPeekLoader.canPeek(URL(string: "https:///nohost")!))
    }

    @Test func systemPagesAreNotPeekedAt() {
        #expect(!LinkPeekLoader.canPeek(URL(string: "linen://settings")!))
    }

    @Test func aTakeawaySplitsAtItsLabel() {
        let point = LinkSummarizer.point(in: "Free tier: 10 GB of storage, no card needed")
        #expect(point?.label == "Free tier")
        #expect(point?.detail == "10 GB of storage, no card needed")
    }

    @Test func aTakeawayLosesItsBullet() {
        #expect(LinkSummarizer.point(in: "- Price: $12 a month")?.label == "Price")
        #expect(LinkSummarizer.point(in: "• Price: $12 a month")?.label == "Price")
    }

    @Test func aSentenceWithoutALabelStaysWhole() {
        let line = "The author argues that the estimate is wrong: the sample was small"
        let point = LinkSummarizer.point(in: line)
        #expect(point?.label.isEmpty == true)
        #expect(point?.detail == line)
    }

    @Test func anEmptyTakeawayIsDropped() {
        #expect(LinkSummarizer.point(in: "   ") == nil)
        #expect(LinkSummarizer.point(in: "-") == nil)
    }

    @Test func aSummaryNeedsSomethingToSay() {
        let gist = LinkGist(gist: "  ", points: ["", " - "])
        #expect(LinkSummarizer.summary(from: gist) == nil)
    }

    @Test func aSummaryStandsOnEitherHalfAlone() {
        let sentence = LinkGist(gist: "A hosted database with a free tier.", points: [])
        #expect(LinkSummarizer.summary(from: sentence)?.gist == "A hosted database with a free tier.")
        #expect(LinkSummarizer.summary(from: sentence)?.points.isEmpty == true)

        let takeaways = LinkGist(gist: " ", points: ["Price: $12 a month"])
        #expect(LinkSummarizer.summary(from: takeaways)?.gist.isEmpty == true)
        #expect(LinkSummarizer.summary(from: takeaways)?.points.count == 1)
    }

    @Test func aSummaryKeepsAtMostFourTakeaways() {
        let gist = LinkGist(
            gist: "A hosted database with a free tier.",
            points: (1...6).map { "Point \($0): detail \($0)" }
        )
        #expect(LinkSummarizer.summary(from: gist)?.points.count == 4)
    }

    @Test func lineBreaksAreFlattened() {
        #expect(LinkSummarizer.sanitize("one\n  two\n\nthree") == "one two three")
    }

    @Test @MainActor func aPageWithNoWordsSaysWhyItHasNone() {
        #expect(LinkPeek.emptyPhase(for: page(didFinishLoading: false)) == .stillLoading)
        #expect(LinkPeek.emptyPhase(for: page(mediaCount: 3)) == .mediaOnly)
        #expect(LinkPeek.emptyPhase(for: page()) == .noText)
    }

    @Test @MainActor func aSlowPageIsNeverCalledMediaOnly() {
        #expect(LinkPeek.emptyPhase(for: page(didFinishLoading: false, mediaCount: 4)) == .stillLoading)
    }

    private func page(didFinishLoading: Bool = true, mediaCount: Int = 0) -> LinkPeekPage {
        LinkPeekPage(
            title: "",
            description: "",
            text: "",
            snapshot: nil,
            didFinishLoading: didFinishLoading,
            mediaCount: mediaCount
        )
    }

    @Test @MainActor func pointingWithoutTheTriggerShowsNothing() {
        let peek = LinkPeek()
        peek.hovered(
            URL(string: "https://example.com"),
            flags: [],
            tabID: UUID(),
            anchor: CGPoint(x: 10, y: 10)
        )
        #expect(peek.shown == nil)
    }

    @Test @MainActor func leavingTheLinkTakesTheCardAway() {
        let peek = LinkPeek()
        peek.hovered(nil, flags: LinkPeek.trigger, tabID: UUID(), anchor: .zero)
        #expect(peek.shown == nil)
    }

    @Test @MainActor func aCardBelongsToTheTabItWasHoveredIn() {
        let peek = LinkPeek()
        peek.suppress()
        peek.hovered(
            URL(string: "https://example.com"),
            flags: LinkPeek.trigger,
            tabID: UUID(),
            anchor: .zero
        )
        #expect(peek.shown == nil)
    }
}
