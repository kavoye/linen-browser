// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Moving a page of a two-page grid. The regression: the removal that starts
/// every move dissolved the pair, and the insertion then found no grid to put
/// the page back into - so picking up either page of a pair destroyed it.
struct SplitPairMoveTests {
    private let a = UUID(), b = UUID()

    private func pair(_ axis: SplitAxis = .sideBySide) -> TabSplits {
        TabSplits().splitting(a, with: b, axis: axis)
    }

    @Test func aPageDroppedBackOnItsOwnSideKeepsThePair() {
        let after = pair().moving(b, beside: a, edge: .right)
        #expect(after.split(containing: a)?.tabs == [a, b])
        #expect(after.split(containing: a)?.axis == .sideBySide)
    }

    @Test func aPageDroppedOnTheOtherSideCrossesOver() {
        let after = pair().moving(b, beside: a, edge: .left)
        #expect(after.split(containing: a)?.tabs == [b, a])
        #expect(after.split(containing: a)?.axis == .sideBySide)
    }

    @Test func aPageDroppedOnAPerpendicularEdgeTurnsThePair() {
        let after = pair().moving(b, beside: a, edge: .top)
        #expect(after.split(containing: a)?.tabs == [b, a])
        #expect(after.split(containing: a)?.axis == .stacked)

        let below = pair().moving(b, beside: a, edge: .bottom)
        #expect(below.split(containing: a)?.tabs == [a, b])
        #expect(below.split(containing: a)?.axis == .stacked)
    }

    @Test func insertingBesideAPageOfNoGridStaysANoOp() {
        let c = UUID()
        #expect(TabSplits().inserting(c, beside: a, edge: .left).isEmpty)
    }

    @Test func leavingThePairStillDissolvesIt() {
        #expect(pair().removing(b).isEmpty)
    }
}

/// The same move as the browser runs it: a pane's grip picked up and put down
/// inside its own pair must leave the split standing.
@MainActor
struct SplitPairMoveModelTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SplitPairMove-\(UUID().uuidString).json")
            )
        )
    }

    @Test func puttingAPaneDownInsideItsOwnPairKeepsTheSplit() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(left)

        model.moveSplitPane(right, beside: left, edge: .right)
        #expect(model.activeSplit?.tabs == [left.id, right.id])
        #expect(model.activeSplit?.axis == .sideBySide)
    }

    @Test func puttingAPaneDownOnAPerpendicularEdgeTurnsTheSplit() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(left)

        model.moveSplitPane(right, beside: left, edge: .bottom)
        #expect(model.activeSplit?.tabs == [left.id, right.id])
        #expect(model.activeSplit?.axis == .stacked)
    }

    @Test func aPaneDroppedClearOfThePageStillLeaves() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        let right = model.newTab(url: URL(string: "https://example.com/b"))
        model.split(left, with: right, axis: .sideBySide)
        model.activate(left)

        model.removeFromSplit(right)
        #expect(model.activeSplit == nil)
        #expect(!model.splits.contains(left.id))
        #expect(!model.splits.contains(right.id))
    }
}
