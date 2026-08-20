// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

/// The bands a drag reads off the row under it. Heights are the app's own:
/// 32pt for one line, 28pt per line plus a 1pt seam for a grid row.
@MainActor
struct SidebarDropGeometryTests {
    private let singleRow = CGRect(x: 0, y: 100, width: 200, height: 32)
    /// A 2×2 or stacked grid row: two 28pt lines and the seam.
    private let tallRow = CGRect(x: 0, y: 100, width: 200, height: 57)
    private let end = SidebarMetrics.splitEndWidth(style: .full)

    private func looseBand(
        x: CGFloat,
        y: CGFloat,
        in frame: CGRect,
        canFold: Bool = true,
        canSplit: Bool = true
    ) -> SidebarDropBand {
        SidebarDropGeometry.looseTabBand(
            at: CGPoint(x: x, y: y),
            in: frame,
            canFold: canFold,
            canSplit: canSplit,
            splitEndWidth: end
        )
    }

    // MARK: - The probe

    @Test func aSingleCarriedRowAimsWithItsOwnMiddle() {
        #expect(SidebarDropGeometry.probeY(cursorY: 500, carriedMidY: 480, carriedHeight: 32) == 480)
    }

    @Test func aCarriedGridAimsWithTheCursor() {
        #expect(SidebarDropGeometry.probeY(cursorY: 500, carriedMidY: 480, carriedHeight: 57) == 500)
    }

    // MARK: - The reorder edge

    @Test func aSingleRowKeepsItsThirds() {
        #expect(abs(SidebarDropGeometry.reorderEdgeHeight(rowHeight: 32) - 10.24) < 0.01)
    }

    @Test func aTallRowsEdgeNeverOutgrowsASingleRows() {
        #expect(
            SidebarDropGeometry.reorderEdgeHeight(rowHeight: 57)
                == SidebarDropGeometry.reorderEdgeHeight(rowHeight: 32)
        )
    }

    // MARK: - Single rows: unchanged behaviour

    @Test func theTopOfARowReordersBefore() {
        #expect(looseBand(x: 100, y: singleRow.minY + 5, in: singleRow) == .before)
    }

    @Test func theBottomOfARowReordersAfter() {
        #expect(looseBand(x: 100, y: singleRow.maxY - 5, in: singleRow) == .after)
    }

    @Test func theMiddleOfARowFolds() {
        #expect(looseBand(x: 100, y: singleRow.midY, in: singleRow) == .fold)
    }

    @Test func theEndsOfTheMiddleSplit() {
        #expect(looseBand(x: singleRow.minX + end - 1, y: singleRow.midY, in: singleRow)
            == .split(leading: true))
        #expect(looseBand(x: singleRow.maxX - end + 1, y: singleRow.midY, in: singleRow)
            == .split(leading: false))
    }

    @Test func withNoSplitOnOfferTheEndsFoldInstead() {
        #expect(looseBand(x: singleRow.minX + 2, y: singleRow.midY, in: singleRow, canSplit: false)
            == .fold)
    }

    @Test func aCarriedFolderCannotFoldSoTheMiddleReorders() {
        #expect(looseBand(x: 100, y: singleRow.midY - 2, in: singleRow, canFold: false, canSplit: false)
            == .before)
        #expect(looseBand(x: 100, y: singleRow.midY + 2, in: singleRow, canFold: false, canSplit: false)
            == .after)
    }

    // MARK: - Grid rows: the fold band grows with the row

    /// The regression: at 32%-thirds a 57pt row spent 18pt on each reorder
    /// edge and squeezed the fold band a 2×2 grid most needs. The edges stay
    /// a single row's, and everything the extra height adds folds.
    @Test func aGridRowsMiddleIsMostlyFold() {
        let edge = SidebarDropGeometry.reorderEdgeHeight(rowHeight: tallRow.height)
        #expect(looseBand(x: 100, y: tallRow.minY + edge + 1, in: tallRow) == .fold)
        #expect(looseBand(x: 100, y: tallRow.midY, in: tallRow) == .fold)
        #expect(looseBand(x: 100, y: tallRow.maxY - edge - 1, in: tallRow) == .fold)
        #expect(tallRow.height - 2 * edge > tallRow.height / 2)
    }

    @Test func aGridRowStillReordersAtItsEdges() {
        #expect(looseBand(x: 100, y: tallRow.minY + 5, in: tallRow) == .before)
        #expect(looseBand(x: 100, y: tallRow.maxY - 5, in: tallRow) == .after)
    }

    /// Four across is one 32pt line; nothing changes for it.
    @Test func aFourAcrossRowBehavesLikeASingleRow() {
        let fourAcross = CGRect(x: 0, y: 100, width: 200, height: 32)
        #expect(looseBand(x: 100, y: fourAcross.midY, in: fourAcross) == .fold)
    }

    // MARK: - Folders and foldered tabs

    @Test func aFolderHeaderFoldsInItsMiddleThird() {
        let header = CGRect(x: 0, y: 100, width: 200, height: 30)
        #expect(SidebarDropGeometry.folderBand(y: header.minY + 5, in: header) == .before)
        #expect(SidebarDropGeometry.folderBand(y: header.midY, in: header) == .fold)
        #expect(SidebarDropGeometry.folderBand(y: header.maxY - 5, in: header) == .after)
    }

    @Test func aTabInsideAFolderOnlyReorders() {
        #expect(SidebarDropGeometry.folderedTabBand(y: singleRow.midY - 1, in: singleRow) == .before)
        #expect(SidebarDropGeometry.folderedTabBand(y: singleRow.midY + 1, in: singleRow) == .after)
    }
}

/// The ends are drop affordances, not row furniture: sized to the column and
/// shown only once the dwell has a combining intent on the row.
@MainActor
struct SidebarSplitEndTests {
    @Test func theCompactColumnKeepsItsEndsNarrow() {
        let icons = SidebarMetrics.splitEndWidth(style: .icons)
        let full = SidebarMetrics.splitEndWidth(style: .full)
        #expect(icons < full)
        #expect(icons * 2 < SidebarMetrics.iconsWidth / 2)
    }

    @Test func theEndsWaitForACombiningIntent() {
        let row = SidebarItem.tab(UUID())
        let other = SidebarItem.tab(UUID())

        #expect(!SidebarRowContext.showsSplitEdges(
            offersSplit: true, item: row, candidate: nil, armed: nil
        ))
        #expect(SidebarRowContext.showsSplitEdges(
            offersSplit: true, item: row, candidate: .fold(row), armed: nil
        ))
        #expect(SidebarRowContext.showsSplitEdges(
            offersSplit: true, item: row, candidate: .split(row, leading: true), armed: nil
        ))
        #expect(SidebarRowContext.showsSplitEdges(
            offersSplit: true, item: row, candidate: nil, armed: .split(row, leading: false)
        ))
        #expect(!SidebarRowContext.showsSplitEdges(
            offersSplit: true, item: row, candidate: .fold(other), armed: nil
        ))
        #expect(!SidebarRowContext.showsSplitEdges(
            offersSplit: false, item: row, candidate: .fold(row), armed: nil
        ))
    }
}
