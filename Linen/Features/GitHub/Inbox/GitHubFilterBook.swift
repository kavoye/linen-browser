// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct GitHubFilterBook {
    private(set) var filters: [GitHubFilter]
    private(set) var selectedID: String
    private let defaults: UserDefaults
    private let persists: Bool

    init(defaults: UserDefaults, isPrivate: Bool) {
        self.defaults = defaults
        persists = !isPrivate
        let saved = isPrivate ? nil : defaults.data(forKey: "github.filters")
        let restored = saved.flatMap { try? JSONDecoder().decode([GitHubFilter].self, from: $0) }
        let initial = restored?.isEmpty == false ? restored! : GitHubFilter.defaults
        filters = initial
        let selected = isPrivate ? nil : defaults.string(forKey: "github.selectedFilter")
        selectedID = initial.first(where: { $0.id == selected })?.id ?? GitHubFilter.inboxID
    }

    var selected: GitHubFilter {
        filters.first { $0.id == selectedID } ?? filters[0]
    }

    var isInbox: Bool {
        selectedID == GitHubFilter.inboxID
    }

    mutating func select(_ id: String) -> Bool {
        guard id == GitHubFilter.inboxID || filters.contains(where: { $0.id == id }), selectedID != id else { return false }
        selectedID = id
        persist()
        return true
    }

    mutating func save(_ filter: GitHubFilter) -> Bool {
        let name = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !query.isEmpty, query.count <= 1000 else { return false }
        let updated = GitHubFilter(id: filter.id, name: name, query: query, symbol: filter.symbol)
        if let index = filters.firstIndex(where: { $0.id == filter.id }) {
            filters[index] = updated
        } else {
            filters.append(updated)
        }
        selectedID = updated.id
        persist()
        return true
    }

    mutating func delete(_ id: String) -> (deleted: Bool, wasSelected: Bool) {
        guard id != GitHubFilter.inboxID, filters.count > 1, filters.contains(where: { $0.id == id }) else {
            return (false, false)
        }
        filters.removeAll { $0.id == id }
        let wasSelected = selectedID == id
        if wasSelected {
            selectedID = GitHubFilter.inboxID
        }
        persist()
        return (true, wasSelected)
    }

    private func persist() {
        guard persists else { return }
        defaults.set(try? JSONEncoder().encode(filters), forKey: "github.filters")
        defaults.set(selectedID, forKey: "github.selectedFilter")
    }
}
