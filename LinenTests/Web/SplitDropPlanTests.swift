// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

/// Where the panes are, in points. The drag and the layout must agree exactly,
/// or a drop lands somewhere the pointer was not.
struct SplitLayoutTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let size = CGSize(width: 1000, height: 800)

    private func layout(_ grid: TabSplit) -> SplitLayout {
        SplitLayout(grid: grid, size: size, gutter: 6)
    }

    private func grid(_ splits: TabSplits, _ id: UUID) -> TabSplit {
        splits.split(containing: id)!
    }

    @Test func twoPagesShareARowLessTheSeam() {
        let grid = TabSplit(a, b, axis: .sideBySide)
        #expect(layout(grid).slot(of: a) == CGRect(x: 0, y: 0, width: 497, height: 800))
        #expect(layout(grid).slot(of: b) == CGRect(x: 503, y: 0, width: 497, height: 800))
    }

    @Test func twoRowsShareTheHeightLessTheSeam() {
        let grid = TabSplit(a, b, axis: .stacked)
        #expect(layout(grid).slot(of: a) == CGRect(x: 0, y: 0, width: 1000, height: 397))
        #expect(layout(grid).slot(of: b) == CGRect(x: 0, y: 403, width: 1000, height: 397))
    }

    /// A line of four takes three seams out of the width, not one - the shape a
    /// grid of rows could not hold, laid out.
    @Test func fourInALineDivideTheWidthThreeTimes() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
        let layout = layout(grid(splits, a))
        let widths = [a, b, c, d].compactMap { layout.slot(of: $0)?.width }
        #expect(layout.seams.count == 3)
        #expect((widths.reduce(0, +) + 18).isApproximately(1000))
        #expect(layout.slot(of: a)?.minX == 0)
        #expect(layout.slot(of: d)?.maxX.isApproximately(1000) == true)
    }

    /// Each line divides only its own box, so a page beside a column keeps the
    /// full height while the column's pages split it.
    @Test func eachLineDividesItsOwnBox() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: b, edge: .bottom)
        let layout = layout(grid(splits, a))
        #expect(layout.slot(of: a)?.height == 800)
        #expect(layout.slot(of: b)?.height.isApproximately(397) == true)
        #expect(layout.slot(of: c)?.height.isApproximately(397) == true)
        #expect(layout.slot(of: b)?.minX == layout.slot(of: c)?.minX)
    }

    /// The band covers the whole content column, so it stands on the pages
    /// along the top edge and on no others.
    @Test func onlyTheTopEdgeStandsUnderTheBar() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: a, edge: .bottom)
        let layout = layout(grid(splits, a))
        #expect(layout.isUnderTopBar(a))
        #expect(layout.isUnderTopBar(b))
        #expect(!layout.isUnderTopBar(c))
        // And the shape agrees with the arithmetic: standing under the bar is
        // the same thing as touching the top of the box.
        #expect(layout.slot(of: a)?.minY == 0)
        #expect(layout.slot(of: c)?.minY != 0)
    }

    @Test func hasNoSlotForAPageItDoesNotHold() {
        #expect(layout(TabSplit(a, b, axis: .sideBySide)).slot(of: d) == nil)
    }

    // MARK: - Seams

    /// A seam knows the two panes it divides, which is what turns a minimum in
    /// points into a minimum share and a pointer into a division.
    @Test func aSeamMeasuresItsOwnPair() {
        let seam = layout(TabSplit(a, b, axis: .sideBySide)).seams[0]
        #expect(seam.axis == .sideBySide)
        #expect(seam.rect.width == 6)
        #expect(seam.pairRect == CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(seam.divisibleLength == 994)
        // The middle of the divider, which is where the hand thinks it is.
        #expect(seam.leadingShare(at: CGPoint(x: 500, y: 400)).isApproximately(0.5))
        #expect(seam.leadingShare(at: CGPoint(x: 3, y: 400)).isApproximately(0))
        #expect(seam.minimumShare(994).isApproximately(0.5))
        #expect(seam.minimumShare(248.5).isApproximately(0.25))
    }

    /// Three panes in a line have two seams, and each measures only its own
    /// pair - so dragging one leaves the third pane where it was.
    @Test func eachSeamOfALineMeasuresADifferentPair() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: b, edge: .right)
        let seams = layout(grid(splits, a)).seams
        #expect(seams.count == 2)
        #expect(seams[0].index == 0)
        #expect(seams[1].index == 1)
        #expect(seams[0].pairRect.maxX < seams[1].pairRect.maxX)
        #expect(seams.map(\.id).count == Set(seams.map(\.id)).count)
    }

    /// A seam inside a column is named by the path to the line it is in, so the
    /// model can find it again without the layout.
    @Test func aNestedSeamNamesItsOwnLine() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: b, edge: .bottom)
        let seams = layout(grid(splits, a)).seams
        let nested = seams.first { $0.axis == .stacked }
        #expect(nested?.groupPath == [1])
        #expect(seams.first { $0.axis == .sideBySide }?.groupPath == [])
    }
}

/// Everywhere a carried page can be put down. The rule the whole thing rests
/// on: every point of the content area belongs to exactly one target, so there
/// is nowhere a release does nothing, and no band to find.
struct SplitDropPlanTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let size = CGSize(width: 1000, height: 800)

    private func plan(_ grid: TabSplit) -> SplitDropPlan {
        SplitDropPlan(grid: grid, size: size, gutter: 6)
    }

    private func pair() -> TabSplit {
        TabSplit(a, b, axis: .sideBySide)
    }

    private func three() -> TabSplit {
        TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: a, edge: .bottom)
            .split(containing: a)!
    }

    private func four() -> TabSplit {
        TabSplits([three()]).inserting(d, beside: b, edge: .bottom).split(containing: a)!
    }

    private func line() -> TabSplit {
        TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: b, edge: .right)
            .inserting(d, beside: c, edge: .right)
            .split(containing: a)!
    }

    // MARK: - One page

    @Test func aSinglePageOffersItsFourHalves() {
        let plan = SplitDropPlan(singlePage: a, size: size)
        let adds = plan.targets.filter { !$0.displaces }
        #expect(plan.targets.count == 4)
        #expect(adds.count == 4)
        #expect(plan.target(at: CGPoint(x: 100, y: 400))?.edge == .left)
        #expect(plan.target(at: CGPoint(x: 900, y: 400))?.edge == .right)
        #expect(plan.target(at: CGPoint(x: 500, y: 60))?.edge == .top)
        #expect(plan.target(at: CGPoint(x: 500, y: 740))?.edge == .bottom)
    }

    /// The band that stacks is a quarter of the page at either end. Nearer the
    /// middle than that, a drop opens beside the page rather than under it.
    @Test func theBandThatStacksIsAQuarterOfThePage() {
        let plan = SplitDropPlan(singlePage: a, size: size)

        #expect(plan.target(at: CGPoint(x: 500, y: 191))?.edge == .top)
        #expect(plan.target(at: CGPoint(x: 500, y: 609))?.edge == .bottom)
        #expect(plan.target(at: CGPoint(x: 490, y: 210))?.edge == .left)
        #expect(plan.target(at: CGPoint(x: 510, y: 590))?.edge == .right)
    }

    @Test func theMiddleOfAPageStaysSideBySide() {
        let plan = SplitDropPlan(singlePage: a, size: size)
        for x in stride(from: CGFloat(40), through: 460, by: 60) {
            #expect(plan.target(at: CGPoint(x: x, y: 300))?.edge == .left)
            #expect(plan.target(at: CGPoint(x: size.width - x, y: 500))?.edge == .right)
        }
        #expect(plan.target(at: CGPoint(x: 40, y: 80))?.edge == .left)
        #expect(plan.target(at: CGPoint(x: 960, y: 720))?.edge == .right)
    }

    // MARK: - Two pages

    /// The window is four squares, and a drag sees nothing smaller: each
    /// quarter of a pair opens that pane's matching half, whichever part of
    /// the quarter the pointer is in.
    @Test func twoPagesAnswerAsFourSquares() {
        let plan = plan(pair())
        for (point, anchor, edge) in [
            (CGPoint(x: 250, y: 200), a, SplitDropZone.top),
            (CGPoint(x: 100, y: 396), a, .top),
            (CGPoint(x: 250, y: 600), a, .bottom),
            (CGPoint(x: 490, y: 404), a, .bottom),
            (CGPoint(x: 750, y: 200), b, .top),
            (CGPoint(x: 750, y: 600), b, .bottom),
        ] {
            let target = plan.target(at: point)
            #expect(target?.anchor == anchor)
            #expect(target?.edge == edge)
            #expect(target?.displaces == false)
        }
    }

    /// The regression that forced the regions onto the panes themselves: with
    /// the seam dragged far, fixed window quarters all matched the big pane's
    /// outcomes and the small pane could not be dropped on at all.
    @Test func anUnevenPairStillAnswersInBothPanes() throws {
        var splits = TabSplits([TabSplit(a, b, axis: .stacked)])
        let grid = try #require(splits.split(containing: a))
        let seam = try #require(SplitLayout(grid: grid, size: size, gutter: 6).seams.first)
        splits = splits.setting(
            seam: seam.index, inGroupAt: seam.groupPath, containing: a,
            leading: 0.8, minimum: 0.1
        )
        let plan = SplitDropPlan(grid: try #require(splits.split(containing: a)), size: size, gutter: 6)

        #expect(plan.target(at: CGPoint(x: 250, y: 300))?.anchor == a)
        #expect(plan.target(at: CGPoint(x: 250, y: 300))?.edge == .left)
        #expect(plan.target(at: CGPoint(x: 750, y: 300))?.edge == .right)
        #expect(plan.target(at: CGPoint(x: 250, y: 750))?.anchor == b)
        #expect(plan.target(at: CGPoint(x: 750, y: 750))?.anchor == b)
        #expect(plan.target(at: CGPoint(x: 750, y: 750))?.edge == .right)
    }

    // MARK: - Three pages

    /// Two panes above one: a pane that is a quarter already takes its place
    /// whole, and the full-height pane beside them divides into its top and
    /// bottom halves.
    @Test func aQuarterPaneIsWholeAndAFullHeightOneDividesInTwo() {
        let splits = TabSplits().splitting(a, with: b, axis: .sideBySide)
            .inserting(c, beside: a, edge: .bottom)
        let plan = SplitDropPlan(grid: splits.split(containing: a)!, size: size, gutter: 6)

        #expect(plan.target(at: CGPoint(x: 250, y: 200))?.anchor == a)
        #expect(plan.target(at: CGPoint(x: 250, y: 200))?.displaces == true)
        #expect(plan.target(at: CGPoint(x: 250, y: 600))?.anchor == c)
        #expect(plan.target(at: CGPoint(x: 250, y: 600))?.displaces == true)

        let right = plan.target(at: CGPoint(x: 750, y: 200))
        #expect(right?.anchor == b)
        #expect(right?.edge == .top)
        #expect(right?.displaces == false)
        #expect(plan.target(at: CGPoint(x: 750, y: 600))?.edge == .bottom)
    }

    // MARK: - Four pages

    /// The case that made this worth rewriting. Four pages are the ceiling, so
    /// every edge of every page means the same thing as its middle - one target
    /// per page, and the whole of each page is droppable.
    @Test func aFullGridIsOneTargetPerPage() {
        let plan = plan(four())
        let adds = plan.targets.filter { !$0.displaces }
        #expect(plan.targets.count == 4)
        #expect(adds.isEmpty)

        let layout = SplitLayout(grid: four(), size: size, gutter: 6)
        for (page, point) in [
            (a, CGPoint(x: 250, y: 200)), (b, CGPoint(x: 750, y: 200)),
            (c, CGPoint(x: 250, y: 600)), (d, CGPoint(x: 750, y: 600)),
        ] {
            let target = plan.target(at: point)
            #expect(target?.slot == layout.slot(of: page))
            #expect(target?.anchor == page)
        }
    }

    /// Four in a line is the shape the old grid could not hold at all, and it
    /// is at the ceiling too - so each of its four narrow panes is one target.
    @Test func aFullLineIsOneTargetPerPage() {
        let plan = plan(line())
        let allTakeovers = plan.targets.allSatisfy(\.displaces)
        #expect(plan.targets.count == 4)
        #expect(allTakeovers)
        #expect(plan.target(at: CGPoint(x: 125, y: 400))?.anchor == a)
        #expect(plan.target(at: CGPoint(x: 875, y: 400))?.anchor == d)
    }

    // MARK: - The whole window

    /// Every point belongs to one, which is what "nowhere a release does
    /// nothing" means. The middles used to be dead ground.
    @Test func everyPointOfTheWindowIsATarget() {
        for grid in [pair(), three(), four(), line()] {
            let plan = plan(grid)
            var uncovered: [CGPoint] = []
            for x in stride(from: CGFloat(10), to: 1000, by: 45) {
                for y in stride(from: CGFloat(10), to: 800, by: 45) {
                    let point = CGPoint(x: x, y: y)
                    if plan.target(at: point) == nil {
                        uncovered.append(point)
                    }
                }
            }
            #expect(uncovered.isEmpty)
        }
    }

    /// The invariant the whole lookup rests on: every outcome divides the page
    /// it landed on, so its slot is that page's rectangle or a part of it.
    ///
    /// A gutter's worth of slack, because it genuinely is not exact: an
    /// arriving page brings another divider with it, and the line it joins
    /// redistributes around that. Break this by more than a divider and asking
    /// the page under the pointer first would start hiding answers.
    @Test func everyTargetLiesInsideItsOwnPage() {
        for grid in [pair(), three(), four(), line()] {
            let plan = plan(grid)
            var strays: [CGRect] = []
            for target in plan.targets {
                let home = plan.panes[target.anchor]?.insetBy(dx: -6, dy: -6)
                if home?.contains(target.slot) != true {
                    strays.append(target.slot)
                }
            }
            #expect(strays.isEmpty)
        }
    }

    /// The page under the pointer decides, always. Weighing the whole window at
    /// once put the boundary between "the right of this page" and "the left of
    /// the next" a few points off the seam, and crossing back and forth over
    /// that is what made a drag feel like it was fighting the hand.
    @Test func thePageUnderThePointerDecides() {
        for grid in [pair(), three(), four(), line()] {
            let plan = plan(grid)
            var wrong: [String] = []
            for (page, home) in plan.panes {
                // Well inside the page, including hard up against each edge.
                for point in [
                    CGPoint(x: home.midX, y: home.midY),
                    CGPoint(x: home.minX + 4, y: home.midY),
                    CGPoint(x: home.maxX - 4, y: home.midY),
                    CGPoint(x: home.midX, y: home.minY + 4),
                    CGPoint(x: home.midX, y: home.maxY - 4),
                ] where plan.target(at: point)?.anchor != page {
                    wrong.append("\(point)")
                }
            }
            #expect(wrong.isEmpty)
        }
    }

    /// Which means the two sides of a seam are two different answers, cleanly:
    /// just left of it divides the page on the left, just right of it divides
    /// the page on the right.
    @Test func eitherSideOfASeamBelongsToItsOwnPage() {
        let plan = plan(pair())
        #expect(plan.target(at: CGPoint(x: 490, y: 400))?.anchor == a)
        #expect(plan.target(at: CGPoint(x: 510, y: 400))?.anchor == b)
    }

    /// No two targets may lead to the same place, or one of them is a region of
    /// the window that cannot be reached.
    @Test func noTwoTargetsMeanTheSameThing() {
        for grid in [pair(), three(), four(), line()] {
            let slots = plan(grid).targets.map { "\($0.slot) \($0.displaces)" }
            #expect(slots.count == Set(slots).count)
        }
    }

    /// A target that takes a page's place is reported against that page, not
    /// against whichever of them was asked first - the marker says whose place
    /// it is taking.
    @Test func aTakeoverNamesThePageItTakesOver() {
        let layout = SplitLayout(grid: four(), size: size, gutter: 6)
        for target in plan(four()).targets where target.displaces {
            #expect(layout.slot(of: target.anchor) == target.slot)
        }
    }

    // MARK: - Moving a page already in the grid

    /// A page in the air is out of the grid while it is carried, so the plan is
    /// drawn for the pages left behind - otherwise a grid at the ceiling would
    /// offer only its own pages' places and never a slot to come back to.
    @Test func carryingAPageLeavesTheSlotItCameFrom() {
        let plan = SplitDropPlan(grid: four(), size: size, gutter: 6, carrying: d)
        let adds = plan.targets.filter { !$0.displaces }
        let aimedAtTheCarriedPage = plan.targets.filter { $0.anchor == d }
        #expect(!adds.isEmpty)
        #expect(aimedAtTheCarriedPage.isEmpty)
    }

    /// Carried out of a full grid, the three left behind answer as squares
    /// too: a square another pane has to itself is the exchange, and the wide
    /// pane's squares put the carried page back beside it.
    @Test func aCarriedPaneExchangesThroughAnothersSquare() {
        let plan = SplitDropPlan(grid: four(), size: size, gutter: 6, carrying: d)
        let exchange = plan.target(at: CGPoint(x: 250, y: 200))
        #expect(exchange?.anchor == a)
        #expect(exchange?.displaces == true)
        let back = plan.target(at: CGPoint(x: 750, y: 200))
        #expect(back?.anchor == b)
        #expect(back?.displaces == false)
    }

    /// One of a pair, picked up: the other has the whole window while it is in
    /// the air, so its four halves are how the two are rearranged. Without this
    /// there was nowhere at all to put it back.
    @Test func carryingOneOfAPairOffersTheOthersHalves() {
        let plan = SplitDropPlan(grid: pair(), size: size, gutter: 6, carrying: a)
        let allAgainstTheSurvivor = plan.targets.allSatisfy { $0.anchor == b }
        #expect(plan.targets.count == 4)
        #expect(allAgainstTheSurvivor)
        #expect(plan.target(at: CGPoint(x: 100, y: 400))?.edge == .left)
    }

    @Test func hasNothingToOfferWithoutAWindow() {
        #expect(SplitDropPlan().targets.isEmpty)
        #expect(SplitDropPlan(grid: pair(), size: .zero, gutter: 6).targets.isEmpty)
        #expect(SplitDropPlan(singlePage: a, size: .zero).targets.isEmpty)
    }
}
