// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing

@testable import Linen

@MainActor
struct SidebarDropGeometryTests {
    private let singleRow = CGRect(x: 0, y: 100, width: 200, height: 32)
    /// A 2×2 or stacked grid row: two 28pt lines and the seam.
    private let tallRow = CGRect(x: 0, y: 100, width: 200, height: 57)

    private func band(_ y: CGFloat, in frame: CGRect) -> SidebarDropBand {
        SidebarDropGeometry.band(y: y, in: frame)
    }

    @Test func theTopHalfOfARowLandsBeforeIt() {
        #expect(band(singleRow.minY + 1, in: singleRow) == .before)
        #expect(band(singleRow.midY - 1, in: singleRow) == .before)
    }

    @Test func theBottomHalfOfARowLandsAfterIt() {
        #expect(band(singleRow.midY, in: singleRow) == .after)
        #expect(band(singleRow.maxY - 1, in: singleRow) == .after)
    }

    @Test func aGridRowSplitsAtItsOwnMiddle() {
        #expect(band(tallRow.midY - 1, in: tallRow) == .before)
        #expect(band(tallRow.midY + 1, in: tallRow) == .after)
    }
}
