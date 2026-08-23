// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct OmniboxItem: Identifiable {
    enum Kind {
        case go
        case search
        case newTab
        case phrase
        case history
        case tab
        case ask
        case action
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    let iconHost: String?
    let shortcut: String
    let alternate: (() -> Void)?
    let run: () -> Void

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String = "",
        symbol: String? = nil,
        iconHost: String? = nil,
        shortcut: String = "",
        alternate: (() -> Void)? = nil,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbol = symbol ?? kind.defaultSymbol
        self.iconHost = iconHost
        self.shortcut = shortcut
        self.alternate = alternate
        self.run = run
    }
}

extension OmniboxItem.Kind {
    var defaultSymbol: String {
        switch self {
        case .go:
            "arrow.up.right"
        case .newTab:
            "plus.rectangle.on.rectangle"
        case .search, .phrase:
            "magnifyingglass"
        case .history:
            "clock"
        case .tab:
            "rectangle.on.rectangle"
        case .ask:
            "sparkle"
        case .action:
            "command"
        }
    }

    var stacksDetail: Bool {
        switch self {
        case .history, .tab:
            true
        case .go, .search, .newTab, .phrase, .ask, .action:
            false
        }
    }
}

struct OmniboxSection: Identifiable {
    let id: String
    let title: String
    var hint: String = ""
    let items: [OmniboxItem]
}

extension Array where Element == OmniboxSection {
    var flattened: [OmniboxItem] {
        flatMap(\.items)
    }

    var itemCounts: [Int] {
        map(\.items.count)
    }
}

enum OmniboxSelection {
    static func moved(from selection: Int, by delta: Int, resultCount: Int) -> Int {
        guard resultCount > 0 else { return 0 }
        return ((selection + delta) % resultCount + resultCount) % resultCount
    }

    static func movedBySection(from selection: Int, by delta: Int, itemCounts: [Int]) -> Int {
        let starts = sectionStarts(itemCounts: itemCounts)
        guard !starts.isEmpty else { return 0 }
        let current = starts.lastIndex { $0 <= selection } ?? 0
        return starts[((current + delta) % starts.count + starts.count) % starts.count]
    }

    static func sectionStarts(itemCounts: [Int]) -> [Int] {
        var start = 0
        var starts: [Int] = []
        for count in itemCounts where count > 0 {
            starts.append(start)
            start += count
        }
        return starts
    }
}

enum Omnibox {
    static var engineName: String {
        SearchURLBuilder.engine.name
    }

    static var isAgentOnly: Bool {
        agentOnlyForTesting ?? BrowserSettings.shared.agentOnlyInput
    }

    @TaskLocal static var agentOnlyForTesting: Bool?

    static let agentOnlyPlaceholder = String(localized: "Ask, or enter website name")

    static func location(for query: String) -> URL? {
        guard BrowserModel.looksLikeLocation(query) else { return nil }
        return query.contains("://") ? URL(string: query) : URL(string: "https://\(query)")
    }

    static func destination(for query: String) -> URL? {
        location(for: query) ?? (isAgentOnly ? nil : SearchURLBuilder.searchURL(for: query))
    }

    static func searchItem(
        for query: String,
        openInNewTab: ((URL) -> Void)? = nil,
        open: @escaping (URL) -> Void
    ) -> OmniboxItem? {
        if let location = location(for: query) {
            return OmniboxItem(
                id: "omnibox-go",
                kind: .go,
                title: query,
                detail: String(localized: "Open website"),
                alternate: openInNewTab.map { openNew in { openNew(location) } }
            ) {
                open(location)
            }
        }
        guard !isAgentOnly else { return nil }
        let search = SearchURLBuilder.searchURL(for: query)
        return OmniboxItem(
            id: "omnibox-search",
            kind: .search,
            title: query,
            detail: String(localized: "Search with \(engineName)"),
            alternate: openInNewTab.map { openNew in { openNew(search) } }
        ) {
            open(search)
        }
    }

    static func newTabItem(for query: String, open: @escaping (URL) -> Void) -> OmniboxItem? {
        guard let destination = destination(for: query) else { return nil }
        let detail: LocalizedStringResource = location(for: query) == nil
            ? "Search with \(engineName) in a new tab"
            : "Open website in a new tab"
        return OmniboxItem(
            id: "omnibox-new-tab",
            kind: .newTab,
            title: query,
            detail: String(localized: detail),
            shortcut: "⇧↩"
        ) {
            open(destination)
        }
    }

    static func topSection(
        query: String,
        openInNewTab: ((URL) -> Void)? = nil,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let row = searchItem(for: query, openInNewTab: openInNewTab, open: open)
        else { return nil }
        let items = [row, openInNewTab.flatMap { newTabItem(for: query, open: $0) }].compactMap { $0 }
        return OmniboxSection(id: "top", title: "", items: items)
    }

    static func phrasesSection(
        query: String,
        phrases: [String],
        limit: Int,
        openInNewTab: ((URL) -> Void)? = nil,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAgentOnly, limit > 0 else { return nil }
        let items = phraseItems(phrases.prefix(limit), openInNewTab: openInNewTab, open: open)
        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "suggestions", title: String(localized: "\(engineName) Suggestions"), items: items)
    }

    static func tabsSection(
        query: String,
        tabs: [BrowserTab],
        limit: Int,
        switchTo: @escaping (BrowserTab) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return nil }
        let needle = query.lowercased()

        let matching = tabs.filter {
            $0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle)
        }
        let items: [OmniboxItem] = mostRelevant(matching, for: query, limit: limit) {
            ($0.title, URL(string: $0.urlString)?.displayAddress ?? $0.urlString)
        }
        .map { tab in
            let host = URL(string: tab.urlString)?.displayHost
            return OmniboxItem(
                id: "omnibox-tab-\(tab.id)",
                kind: .tab,
                title: tab.title,
                detail: [host, String(localized: "Opened Tab")].compactMap { $0 }.joined(separator: " • "),
                iconHost: host
            ) {
                switchTo(tab)
            }
        }

        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "tabs", title: String(localized: "Switch to Tab"), items: items)
    }

    static func relevance(title: String, address: String, for query: String) -> Int {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return 0 }
        let title = title.lowercased()
        let address = address.lowercased()
        let host = address.split(separator: "/").first.map(String.init) ?? address

        var score = 0
        if host.hasPrefix(needle) {
            score += 1000
        } else if host.contains(".\(needle)") {
            score += 600
        } else if host.contains(needle) {
            score += 300
        }

        if title.hasPrefix(needle) {
            score += 400
        } else if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains(where: { $0.hasPrefix(needle) }) {
            score += 200
        } else if title.contains(needle) {
            score += 80
        }

        if address.contains(needle) {
            score += 40
        }

        return score - min(address.count / 4, 40)
    }

    private static func mostRelevant<T>(
        _ candidates: [T],
        for query: String,
        limit: Int,
        fields: (T) -> (title: String, address: String)
    ) -> [T] {
        candidates.enumerated()
            .map { entry -> (index: Int, item: T, score: Int) in
                let (title, address) = fields(entry.element)
                return (entry.offset, entry.element, relevance(title: title, address: address, for: query))
            }
            .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
            .prefix(limit)
            .map(\.item)
    }

    private static func phraseItems(
        _ phrases: some Sequence<String>,
        openInNewTab: ((URL) -> Void)? = nil,
        open: @escaping (URL) -> Void
    ) -> [OmniboxItem] {
        guard !isAgentOnly else { return [] }
        return phrases.map { phrase in
            let search = SearchURLBuilder.searchURL(for: phrase)
            return OmniboxItem(
                id: "omnibox-phrase-\(phrase)",
                kind: .phrase,
                title: phrase,
                alternate: openInNewTab.map { openNew in { openNew(search) } }
            ) {
                open(search)
            }
        }
    }

    static func historySection(
        query: String,
        store: HistoryStore,
        limit: Int,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return nil }

        let candidates = store.search(query, limit: max(limit * 10, 30))
        let items: [OmniboxItem] = mostRelevant(candidates, for: query, limit: limit) { entry in
            (entry.title, URL(string: entry.url)?.displayAddress ?? entry.url)
        }
        .compactMap { entry in
            guard let url = URL(string: entry.url) else { return nil }
            let host = url.displayHost ?? entry.url
            return OmniboxItem(
                id: "omnibox-history-\(entry.id)",
                kind: .history,
                title: entry.title,
                detail: url.displayAddress ?? host,
                iconHost: url.displayHost
            ) {
                open(url)
            }
        }

        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "history", title: String(localized: "History"), items: items)
    }
}
