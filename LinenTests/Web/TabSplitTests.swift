// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

/// The tree of pages shown at once.
///
/// Written as text: `(a b)` is a line running left to right, `[a b]` one
/// running top to bottom, and they nest. Every shape below is one a grid of
/// rows could not hold, or one it held only by accident.
struct TabSplitTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    private func pair(_ axis: SplitAxis = .sideBySide) -> TabSplits {
        TabSplits().splitting(a, with: b, axis: axis)
    }

    private func name(_ id: UUID) -> String {
        switch id {
        case a:
            "a"
        case b:
            "b"
        case c:
            "c"
        case d:
            "d"
        case e:
            "e"
        default:
            "?"
        }
    }

    private func shape(_ node: SplitNode) -> String {
        switch node.content {
        case .page(let id):
            name(id)
        case .group(let axis, let children):
            (axis == .sideBySide ? "(" : "[")
                + children.map(shape).joined(separator: " ")
                + (axis == .sideBySide ? ")" : "]")
        }
    }

    private func shape(_ splits: TabSplits, containing id: UUID) -> String? {
        splits.split(containing: id).map { shape($0.root) }
    }

    private func shares(_ splits: TabSplits, containing id: UUID) -> [CGFloat]? {
        splits.split(containing: id)?.root.children.map(\.share)
    }

    // MARK: - The first two

    @Test func twoPagesMakeALine() {
        #expect(shape(pair(.sideBySide), containing: a) == "(a b)")
        #expect(shape(pair(.stacked), containing: a) == "[a b]")
    }

    @Test func startsEvenlyDivided() {
        #expect(shares(pair(), containing: a) == [0.5, 0.5])
    }

    @Test func refusesToPairAPageWithItself() {
        #expect(TabSplits().splitting(a, with: a, axis: .sideBySide).isEmpty)
    }

    /// A page can share one window, not two.
    @Test func breaksTheOldGridWhenEitherPageJoinsANewOne() {
        let splits = pair().splitting(b, with: c, axis: .sideBySide)
        #expect(splits.others(of: b) == [c])
        #expect(!splits.contains(a))
        #expect(splits.splits.count == 1)
    }

    // MARK: - Growing

    /// The rule the whole shape rests on: an edge whose direction the line
    /// already runs joins that line, and one that runs the other way turns the
    /// page it landed on into a line of its own. There is no third answer, and
    /// no arrangement in which an edge means something other than what it says.
    @Test func anEdgeAlongTheLineJoinsIt() {
        #expect(shape(pair().inserting(c, beside: b, edge: .right), containing: a) == "(a b c)")
        #expect(shape(pair().inserting(c, beside: a, edge: .left), containing: a) == "(c a b)")
    }

    @Test func anEdgeAcrossTheLineDividesThePageItLandedOn() {
        #expect(shape(pair().inserting(c, beside: a, edge: .bottom), containing: a) == "([a c] b)")
        #expect(shape(pair().inserting(c, beside: b, edge: .top), containing: a) == "(a [c b])")
    }

    /// The shape a grid of at most two rows of at most two cannot hold at all,
    /// and the one this whole rewrite was for.
    @Test func fourPagesCanShareOneLine() {
        let splits = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
        #expect(shape(splits, containing: a) == "(a b c d)")
        #expect(shares(splits, containing: a)?.count == 4)
    }

    /// And so can this one: one page beside a column of three.
    @Test func onePageCanStandBesideAColumn() {
        let splits = pair()
            .inserting(c, beside: b, edge: .bottom)
            .inserting(d, beside: c, edge: .bottom)
        #expect(shape(splits, containing: a) == "(a [b c d])")
    }

    /// And the square is still a square, reached by dividing each of two pages
    /// rather than by filling a second row.
    @Test func stillMakesASquare() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .inserting(d, beside: b, edge: .bottom)
        #expect(shape(splits, containing: a) == "([a c] [b d])")
        #expect(splits.split(containing: a)?.isFull == true)
    }

    /// A line inside a line of the same direction is the same line written
    /// twice, so it is folded away - which is what keeps four in a row a single
    /// line of four, with three dividers that all behave alike.
    @Test func neverNestsALineInsideOneRunningTheSameWay() {
        let splits = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: b, edge: .left)
        #expect(shape(splits, containing: a) == "(a d b c)")
    }

    @Test func readsFromTheTopLeft() {
        let splits = pair().inserting(c, beside: a, edge: .bottom)
        #expect(splits.split(containing: a)?.tabs == [a, c, b])
        #expect(splits.split(containing: a)?.leader == a)
    }

    // MARK: - The page ceiling

    /// Four is the ceiling, so a fifth has genuinely nowhere to go and the page
    /// it was dropped on gives way. Its tab is not closed - the caller leaves it
    /// where it sits. This is the only case in which an edge does not divide.
    @Test func aFifthPageTakesThePlaceOfThePageItLandedOn() {
        let full = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
        for edge in SplitDropZone.edges {
            let splits = full.inserting(e, beside: b, edge: edge)
            #expect(splits.split(containing: e)?.count == 4)
            #expect(!splits.contains(b))
            #expect(shape(splits, containing: e) == "(a e c d)")
        }
    }

    /// Short of the ceiling nothing is ever thrown out to make room, whatever
    /// shape the tree is in - the grid refusing to grow while it still had space
    /// is what made the fourth drop feel broken.
    @Test func nothingIsThrownOutWhileThereIsRoom() {
        let three = pair().inserting(c, beside: a, edge: .bottom)
        for anchor in [a, b, c] {
            for edge in SplitDropZone.edges {
                let splits = three.inserting(d, beside: anchor, edge: edge)
                #expect(splits.split(containing: d)?.count == 4)
            }
        }
    }

    // MARK: - The middle

    /// An arriving page put down on the middle of another takes its place.
    @Test func theMiddleTakesThePagesPlace() {
        let splits = pair().inserting(c, beside: a, edge: .centre)
        #expect(shape(splits, containing: c) == "(c b)")
        #expect(!splits.contains(a))
    }

    /// A page already in the grid put down on the middle of another changes
    /// places with it, because rearranging pages must not lose one.
    @Test func theMiddleExchangesTwoPagesOfOneGrid() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .moving(c, beside: b, edge: .centre)
        #expect(shape(splits, containing: a) == "([a b] c)")
        #expect(splits.split(containing: a)?.count == 3)
    }

    // MARK: - Leaving

    @Test func aPageLeavingClosesTheLineItWasAlone() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .removing(c)
        #expect(shape(splits, containing: a) == "(a b)")
    }

    @Test func aPageLeavingGivesItsRoomToThePagesBesideIt() {
        let splits = pair()
            .inserting(c, beside: b, edge: .right)
            .removing(b)
        let shares = shares(splits, containing: a)
        #expect(shape(splits, containing: a) == "(a c)")
        #expect((shares?.reduce(0, +) ?? 0).isApproximately(1) == true)
    }

    /// A grid of one is not a grid.
    @Test func theSecondToLastPageLeavingClosesTheGrid() {
        #expect(pair().removing(b).isEmpty)
    }

    @Test func dissolvingTakesEveryPageWithIt() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .dissolving(containing: c)
        #expect(splits.isEmpty)
    }

    @Test func leavesOtherGridsAlone() {
        let splits = pair()
            .splitting(c, with: d, axis: .stacked)
            .removing(a)
        #expect(splits.others(of: c) == [d])
        #expect(splits.splits.count == 1)
    }

    // MARK: - Rearranging

    /// Taking the page out first always leaves room for it to go back, so a
    /// move is the same operation as an arrival and can never reach the ceiling.
    @Test func aMoveNeverLosesAPage() {
        let full = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
        for anchor in [a, b, c] {
            for edge in SplitDropZone.edges {
                #expect(full.moving(d, beside: anchor, edge: edge).split(containing: d)?.count == 4)
            }
        }
    }

    @Test func movingAPageWithinTheGrid() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .moving(c, beside: b, edge: .bottom)
        #expect(shape(splits, containing: a) == "(a [b c])")
    }

    @Test func swapsTwoPagesWithoutResizingThem() {
        let splits = pair()
            .setting(seam: 0, inGroupAt: [], containing: a, leading: 0.7, minimum: 0.1)
            .swappingRow(containing: a)
        #expect(shape(splits, containing: a) == "(b a)")
        #expect(shares(splits, containing: a)?.first?.isApproximately(0.7) == true)
    }

    /// "Swap" describes a line of exactly two. A line of three has no one page
    /// to swap with, so the command must not offer itself.
    @Test func onlyALineOfTwoHasAPageToSwapWith() {
        let three = pair().inserting(c, beside: b, edge: .right)
        #expect(three.split(containing: a)?.sibling(of: a) == nil)
        #expect(pair().split(containing: a)?.sibling(of: a) == b)
    }

    @Test func changesTheAxisOfTwoPages() {
        let splits = pair(.sideBySide).setting(axis: .stacked, containing: b)
        #expect(shape(splits, containing: a) == "[a b]")
        #expect(splits.split(containing: a)?.axis == .stacked)
    }

    /// Three or four pages have a shape, not an axis, so the word does not
    /// apply and must not rearrange them.
    @Test func threePagesHaveNoAxis() {
        let splits = pair().inserting(c, beside: a, edge: .bottom)
        #expect(splits.split(containing: a)?.axis == nil)
        #expect(splits.setting(axis: .stacked, containing: a) == splits)
    }

    // MARK: - Dividers

    /// An arriving page takes half of the page it landed on and leaves the
    /// others alone, so a line of three is not three equal thirds.
    @Test func anArrivingPageTakesHalfOfTheOneItLandedOn() {
        let shares = shares(pair().inserting(c, beside: b, edge: .right), containing: a)
        #expect(shares?[0].isApproximately(0.5) == true)
        #expect(shares?[1].isApproximately(0.25) == true)
        #expect(shares?[2].isApproximately(0.25) == true)
    }

    /// A divider moves the two panes it stands between and no others. The third
    /// pane of a line of three keeps exactly what it had - which a divider
    /// working on the whole line rather than on its own pair could not manage.
    @Test func aDividerMovesOnlyItsOwnPair() {
        let three = pair().inserting(c, beside: b, edge: .right)
        let splits = three.setting(seam: 0, inGroupAt: [], containing: a, leading: 0.75, minimum: 0.1)
        let shares = shares(splits, containing: a)
        #expect(shares?[0].isApproximately(0.5625) == true)
        #expect(shares?[1].isApproximately(0.1875) == true)
        #expect(shares?[2].isApproximately(0.25) == true)
    }

    /// Past these the smaller pane stops being a page and becomes a stripe.
    @Test func clampsADividerAtBothEnds() {
        let wide = pair().setting(seam: 0, inGroupAt: [], containing: a, leading: 3, minimum: 0.1)
        let narrow = pair().setting(seam: 0, inGroupAt: [], containing: a, leading: -1, minimum: 0.1)
        #expect(shares(wide, containing: a)?.first?.isApproximately(TabSplit.shareRange.upperBound) == true)
        #expect(shares(narrow, containing: a)?.first?.isApproximately(TabSplit.shareRange.lowerBound) == true)
    }

    /// The share alone cannot say how narrow is too narrow: a sixth of a small
    /// window is a stripe and a sixth of a large one is a page. The caller sends
    /// the minimum in as a share of the pair, worked out from its length.
    @Test func clampsADividerByLengthWhenThatBindsFirst() {
        let splits = pair().setting(seam: 0, inGroupAt: [], containing: a, leading: 0.05, minimum: 0.4)
        #expect(shares(splits, containing: a)?.first?.isApproximately(0.4) == true)
    }

    @Test func ignoresADividerThatIsNotThere() {
        let splits = pair()
        #expect(splits.setting(seam: 4, inGroupAt: [], containing: a, leading: 0.7, minimum: 0.1) == splits)
        #expect(splits.setting(seam: 0, inGroupAt: [9], containing: a, leading: 0.7, minimum: 0.1) == splits)
    }

    // MARK: - Which pages the toolbar covers

    /// The band covers the whole content column, so it stands on the pages
    /// along the top edge - which is a question about the shape, not the size.
    @Test func saysWhichPagesStandUnderTheBar() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .inserting(d, beside: b, edge: .bottom)
        let grid = splits.split(containing: a)
        #expect(shape(splits, containing: a) == "([a c] [b d])")
        #expect(grid?.isUnderTopBar(a) == true)
        #expect(grid?.isUnderTopBar(b) == true)
        #expect(grid?.isUnderTopBar(c) == false)
        #expect(grid?.isUnderTopBar(d) == false)
    }

    @Test func everyPageOfALineStandsUnderTheBar() {
        let splits = pair().inserting(c, beside: b, edge: .right)
        let grid = splits.split(containing: a)
        let all = [a, b, c].allSatisfy { grid?.isUnderTopBar($0) == true }
        #expect(all)
    }

    // MARK: - The sidebar's one row

    @Test func theGridIsLedByThePageInItsTopLeft() {
        let splits = pair().inserting(c, beside: a, edge: .top)
        #expect(splits.splitLed(by: c) != nil)
        #expect(splits.splitLed(by: a) == nil)
        #expect(splits.followerTabs == [a, b])
        #expect(splits.isFollower(a))
    }

    /// The list's row is the window's own shape, however many pages wide: the
    /// row's job is to say where each page is, not only which pages these are.
    @Test func theSidebarRowMirrorsTheWindowsShape() throws {
        let four = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
        let row = try #require(four.split(containing: a)?.sidebarShape)
        #expect(shape(row.root) == "(a b c d)")
        #expect(four.split(containing: a)?.sidebarLineCount == 1)

        let threeOverOne = pair()
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: a, edge: .bottom)
        #expect(threeOverOne.split(containing: d)?.sidebarLineCount == 2)
    }

    /// And only the shape: the shares are the window's business. A pane pulled
    /// to 70/30 stays a readable cell.
    @Test func theSidebarRowDividesEveryLineEvenly() throws {
        var splits = pair().inserting(c, beside: b, edge: .right)
        let grid = try #require(splits.split(containing: a))
        let layout = SplitLayout(grid: grid, size: CGSize(width: 1200, height: 800), gutter: 6)
        let seam = try #require(layout.seams.first)
        splits = TabSplits([grid]).setting(
            seam: seam.index, inGroupAt: seam.groupPath, containing: a,
            leading: 0.2, minimum: 0.15
        )

        let row = try #require(splits.split(containing: a)?.sidebarShape)
        #expect(shape(row.root) == "(a b c)")
        #expect(row.root.children.allSatisfy { abs($0.share - 1 / 3) < 0.001 })
    }

    // MARK: - Writing it down

    /// The arrangement is stored as its tree, so anything that survives a
    /// launch has to survive this.
    @Test func aTreeSurvivesBeingWrittenDown() throws {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .inserting(d, beside: b, edge: .right)
        let grid = try #require(splits.split(containing: a))
        let data = try JSONEncoder().encode(grid.root)
        let back = try JSONDecoder().decode(SplitNode.self, from: data)
        #expect(TabSplit(root: back) == grid)
    }

    // MARK: - Reconciliation

    /// The self-healing half: a call site that closes a tab and forgets to
    /// remove it must degrade to a smaller grid rather than to a pane holding
    /// a page that is gone.
    @Test func trimsAGridToThePagesThatStillExist() {
        let splits = pair()
            .inserting(c, beside: a, edge: .bottom)
            .reconciled(against: [a, b])
        #expect(shape(splits, containing: a) == "(a b)")
    }

    @Test func dropsAGridLeftWithOnePage() {
        #expect(pair().reconciled(against: [a]).isEmpty)
    }

    /// A stored session that names one page in two grids would draw it in two
    /// panes at once. The first keeps it; the second is a grid of one, which
    /// is no grid.
    @Test func neverLetsOnePageBelongToTwoGrids() {
        let splits = TabSplits([
            TabSplit(a, b, axis: .sideBySide),
            TabSplit(b, c, axis: .sideBySide),
        ]).reconciled(against: [a, b, c])
        #expect(splits.splits.count == 1)
        #expect(splits.others(of: a) == [b])
        #expect(!splits.contains(c))
    }

    /// A tree read back from a session may say anything at all. None of it may
    /// reach the layout, which trusts what it is given.
    @Test func refusesATreeThatIsNotAGrid() {
        #expect(TabSplit(root: .page(a)) == nil)
        #expect(TabSplit(root: .group(.sideBySide, [])) == nil)
        #expect(TabSplit(root: .group(.sideBySide, [.page(a)])) == nil)
    }
}

/// What each edge asks for. Where those edges begin and end is
/// `SplitDropPlan`'s question, not this one's.
struct SplitDropZoneTests {
    @Test func saysWhichArrangementEachEdgeAsksFor() {
        #expect(SplitDropZone.left.axis == .sideBySide)
        #expect(SplitDropZone.bottom.axis == .stacked)
        #expect(SplitDropZone.none.axis == nil)
        #expect(SplitDropZone.centre.axis == nil)
        #expect(SplitDropZone.left.placesDroppedTabFirst)
        #expect(SplitDropZone.top.placesDroppedTabFirst)
        #expect(!SplitDropZone.right.placesDroppedTabFirst)
        #expect(!SplitDropZone.bottom.placesDroppedTabFirst)
        #expect(SplitDropZone.edges.count == 4)
        #expect(!SplitDropZone.edges.contains(.centre))
    }
}

extension CGFloat {
    /// Shares are divided and multiplied on their way through the tree, so they
    /// come back as very nearly what they went in as.
    func isApproximately(_ other: CGFloat, within slack: CGFloat = 0.0001) -> Bool {
        abs(self - other) < slack
    }
}
