// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct SidebarSectionPlan: Equatable {
    struct Row: Equatable {
        var item: SidebarItem
        var isKept: Bool
        var isCarried: Bool

        init(item: SidebarItem, isKept: Bool, isCarried: Bool = false) {
            self.item = item
            self.isKept = isKept
            self.isCarried = isCarried
        }
    }

    var rows: [Row] = []
    var wasKept = false

    func cut(pinsCarried: Bool) -> Int {
        var cut = 0
        for (index, row) in rows.enumerated() {
            if row.isCarried {
                let next = rows[rows.index(after: index)...].first { !$0.isCarried }
                guard pinsCarried || next?.isKept == true else { break }
                cut += 1
                continue
            }
            guard row.isKept else { break }
            cut += 1
        }
        return cut == rows.count ? 0 : cut
    }

    func lands(before isBefore: Bool, of anchor: SidebarItem) -> Bool {
        guard let row = rows.first(where: { $0.item == anchor }) else { return false }
        if row.isKept {
            return true
        }
        guard isBefore, wasKept else { return false }
        return rows.first { !$0.isCarried }?.item == anchor
    }
}
