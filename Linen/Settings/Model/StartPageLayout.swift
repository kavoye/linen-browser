// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct StartPageLayout: Equatable {
    static let standard = StartPageLayout(order: StartPageSection.allCases, hidden: [], hiddenFrequentHosts: [])

    var order: [StartPageSection]
    var hidden: Set<StartPageSection>
    var hiddenFrequentHosts: Set<String>

    init(order: [StartPageSection], hidden: Set<StartPageSection>, hiddenFrequentHosts: Set<String>) {
        self.order = order
        self.hidden = hidden
        self.hiddenFrequentHosts = hiddenFrequentHosts
    }

    init(storedOrder: [String]?, hidden: [String]?, hiddenFrequentHosts: [String]?) {
        order = Self.resolveOrder(storedOrder)
        self.hidden = Set((hidden ?? []).compactMap(StartPageSection.init(rawValue:)))
        self.hiddenFrequentHosts = Set(hiddenFrequentHosts ?? [])
    }

    func shows(_ section: StartPageSection) -> Bool {
        !hidden.contains(section)
    }

    mutating func set(_ section: StartPageSection, shown: Bool) {
        if shown {
            hidden.remove(section)
        } else {
            hidden.insert(section)
        }
    }

    mutating func hideFrequentSite(host: String) {
        hiddenFrequentHosts.insert(host.lowercased())
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        let moved = source.map { order[$0] }
        var order = order
        for index in source.sorted(by: >) {
            order.remove(at: index)
        }
        let insertion = destination - source.count(where: { $0 < destination })
        order.insert(contentsOf: moved, at: min(max(insertion, 0), order.count))
        self.order = order
    }

    private static func resolveOrder(_ stored: [String]?) -> [StartPageSection] {
        let known = stored?.compactMap(StartPageSection.init(rawValue:)) ?? []
        var order = known
        for section in StartPageSection.allCases where !order.contains(section) {
            let following = StartPageSection.allCases
                .drop { $0 != section }
                .dropFirst()
                .first { order.contains($0) }
            if let following, let index = order.firstIndex(of: following) {
                order.insert(section, at: index)
            } else {
                order.append(section)
            }
        }
        return order
    }
}
