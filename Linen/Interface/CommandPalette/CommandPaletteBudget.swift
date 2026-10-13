// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum CommandPaletteBudget {
    static let typing = 12
    static let resting = 14

    struct Slot {
        let section: OmniboxSection
        let floor: Int
        let quota: Int

        init(_ section: OmniboxSection?, floor: Int, quota: Int) {
            self.section = section ?? OmniboxSection(id: "", title: "", items: [])
            self.floor = floor
            self.quota = quota
        }
    }

    static func fit(_ slots: [Slot], total: Int) -> [OmniboxSection] {
        let caps = slots.map { min($0.quota, $0.section.items.count) }
        var granted = slots.indices.map { min(slots[$0].floor, caps[$0]) }
        var spent = granted.reduce(0, +)

        var index = granted.count - 1
        while spent > total, index >= 0 {
            let drop = min(granted[index], spent - total)
            granted[index] -= drop
            spent -= drop
            index -= 1
        }

        var grew = true
        while spent < total, grew {
            grew = false
            for slot in granted.indices where spent < total && granted[slot] < caps[slot] {
                granted[slot] += 1
                spent += 1
                grew = true
            }
        }

        return slots.indices.compactMap { index in
            let section = slots[index].section
            guard granted[index] > 0 else { return nil }
            return OmniboxSection(
                id: section.id,
                title: section.title,
                hint: section.hint,
                items: Array(section.items.prefix(granted[index]))
            )
        }
    }
}
