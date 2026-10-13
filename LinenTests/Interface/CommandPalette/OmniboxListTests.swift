// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Testing

@testable import Linen

/// The flat-list arithmetic under the omnibox results: how tall the panel
/// must be for the rows, headings and gaps it shows.
struct OmniboxListTests {
    private func item(_ id: String, kind: OmniboxItem.Kind = .action) -> OmniboxItem {
        OmniboxItem(id: id, kind: kind, title: id) {}
    }

    private func sections(_ shape: [(title: String, count: Int)]) -> [OmniboxSection] {
        shape.enumerated().map { index, section in
            OmniboxSection(
                id: "s\(index)",
                title: section.title,
                items: (0..<section.count).map { item("s\(index)r\($0)") }
            )
        }
    }

    @Test func heightCountsRowsHeadersGapsAndPadding() {
        let list = sections([("", 1), ("Open Tabs", 2)])
        let density = OmniboxList.Density.compact
        let expected = density.rowHeight * 3
            + density.headerHeight
            + density.sectionGap
            + density.padding * 2
        #expect(OmniboxList.height(of: list, density: density) == expected)
    }

    /// A history or tab row is taller by its second line, and the panel must
    /// grow with it or the last row is clipped.
    @Test func stackedRowsMakeThePanelTaller() {
        let stacked = [OmniboxSection(id: "s", title: "", items: [item("a", kind: .history)])]
        let plain = [OmniboxSection(id: "s", title: "", items: [item("a")])]
        let density = OmniboxList.Density.regular
        let difference = OmniboxList.height(of: stacked, density: density)
            - OmniboxList.height(of: plain, density: density)
        #expect(difference == density.stackedRowHeight - density.rowHeight)
    }

    @Test func anEmptyListIsJustThePadding() {
        let density = OmniboxList.Density.regular
        #expect(OmniboxList.height(of: [], density: density) == density.padding * 2)
    }
}
