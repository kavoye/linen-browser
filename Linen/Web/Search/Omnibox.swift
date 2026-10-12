// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct OmniboxSuggestionPreview {
    private(set) var sections: [OmniboxSection]?
    private(set) var query: String?

    mutating func select(at index: Int, in results: [OmniboxSection], query input: String) -> String? {
        let items = results.flattened
        guard items.indices.contains(index) else { return nil }
        if sections == nil {
            sections = results
            query = input
        }
        return items[index].completionText ?? query ?? input
    }

    mutating func clear() {
        sections = nil
        query = nil
    }
}

struct OmniboxItem: Identifiable {
    enum Kind {
        case go
        case search
        case newTab
        case phrase
        case history
        case tab
        case archived
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
    let completionText: String?
    let alternate: (() -> Void)?
    let remove: (() -> Void)?
    let run: () -> Void

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String = "",
        symbol: String? = nil,
        iconHost: String? = nil,
        shortcut: String = "",
        completionText: String? = nil,
        alternate: (() -> Void)? = nil,
        remove: (() -> Void)? = nil,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbol = symbol ?? kind.defaultSymbol
        self.iconHost = iconHost
        self.shortcut = shortcut
        self.completionText = completionText ?? {
            switch kind {
            case .go, .search, .phrase, .newTab:
                title
            default:
                nil
            }
        }()
        self.alternate = alternate
        self.remove = remove
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
        case .archived:
            "archivebox"
        case .ask:
            "sparkle"
        case .action:
            "command"
        }
    }

    var stacksDetail: Bool {
        switch self {
        case .history, .tab, .archived:
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

    static func isAgentOnly(settings: BrowserSettings) -> Bool {
        agentOnlyForTesting ?? settings.agentOnlyInput
    }

    @TaskLocal static var agentOnlyForTesting: Bool?

    static let agentOnlyPlaceholder = String(localized: "Ask, or enter website name")

    static func location(for query: String) -> URL? {
        guard BrowserModel.looksLikeLocation(query) else { return nil }
        return query.contains("://") ? URL(string: query) : URL(string: "https://\(query)")
    }

    static func destination(for query: String, settings: BrowserSettings = .shared) -> URL? {
        location(for: query) ?? (isAgentOnly(settings: settings) ? nil : SearchURLBuilder.searchURL(for: query, settings: settings))
    }

    static func searchItem(
        for query: String,
        symbol: String? = nil,
        openInNewTab: ((URL) -> Void)? = nil,
        openInCurrentTab: ((URL) -> Void)? = nil,
        settings: BrowserSettings = .shared,
        open: @escaping (URL) -> Void
    ) -> OmniboxItem? {
        if let location = location(for: query) {
            return OmniboxItem(
                id: "omnibox-go",
                kind: .go,
                title: query,
                detail: String(localized: "Open website"),
                symbol: symbol,
                alternate: openInCurrentTab.map { openCurrent in { openCurrent(location) } }
                    ?? openInNewTab.map { openNew in { openNew(location) } }
            ) {
                open(location)
            }
        }
        guard !isAgentOnly(settings: settings) else { return nil }
        let search = SearchURLBuilder.searchURL(for: query, settings: settings)
        return OmniboxItem(
            id: "omnibox-search",
            kind: .search,
            title: query,
            detail: String(localized: "Search with \(SearchURLBuilder.engine(settings: settings).name)"),
            symbol: symbol,
            alternate: openInCurrentTab.map { openCurrent in { openCurrent(search) } }
                ?? openInNewTab.map { openNew in { openNew(search) } }
        ) {
            open(search)
        }
    }

    static func newTabItem(for query: String, settings: BrowserSettings = .shared, open: @escaping (URL) -> Void) -> OmniboxItem? {
        guard let destination = destination(for: query, settings: settings) else { return nil }
        let detail: LocalizedStringResource = location(for: query) == nil
            ? "Search with \(SearchURLBuilder.engine(settings: settings).name) in a new tab"
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
        symbol: String? = nil,
        openInNewTab: ((URL) -> Void)? = nil,
        openInCurrentTab: ((URL) -> Void)? = nil,
        settings: BrowserSettings = .shared,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let row = searchItem(
                  for: query,
                  symbol: symbol,
                  openInNewTab: openInNewTab,
                  openInCurrentTab: openInCurrentTab,
                  settings: settings,
                  open: open
              )
        else { return nil }
        let items = [row, openInNewTab.flatMap { newTabItem(for: query, settings: settings, open: $0) }].compactMap { $0 }
        return OmniboxSection(id: "top", title: "", items: items)
    }

    static func phrasesSection(
        query: String,
        phrases: [String],
        limit: Int,
        openInNewTab: ((URL) -> Void)? = nil,
        openInCurrentTab: ((URL) -> Void)? = nil,
        settings: BrowserSettings = .shared,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isAgentOnly(settings: settings), limit > 0 else { return nil }
        let items = phraseItems(
            phrases.prefix(limit),
            openInNewTab: openInNewTab,
            openInCurrentTab: openInCurrentTab,
            settings: settings,
            open: open
        )
        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "suggestions", title: String(localized: "\(SearchURLBuilder.engine(settings: settings).name) Suggestions"), items: items)
    }

    static func pagesSection(
        query: String,
        tabs: [BrowserTab],
        hiding activeTabID: UUID? = nil,
        store: HistoryStore,
        limit: Int,
        switchTo: @escaping (BrowserTab) -> Void,
        openInCurrentTab: ((URL) -> Void)? = nil,
        open: @escaping (URL) -> Void
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return nil }
        let needle = query.lowercased()

        let visited = store.search(query, limit: max(limit * 10, 30))
        let frecencyByURL = Dictionary(
            visited.map { ($0.url, frecency(visitCount: $0.visitCount, lastVisit: $0.lastVisit)) },
            uniquingKeysWith: max
        )
        let openTabs = tabs.filter {
            $0.id != activeTabID
                && ($0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle))
        }
        let openURLs = Set(tabs.map(\.urlString))

        let candidates: [PageCandidate] =
            openTabs.map { tab in
                PageCandidate(
                    item: tabItem(tab, switchTo: switchTo),
                    title: tab.title,
                    address: URL(string: tab.urlString)?.displayAddress ?? tab.urlString,
                    bonus: (frecencyByURL[tab.urlString] ?? 0) + openTabBonus
                )
            }
            + visited.filter { !openURLs.contains($0.url) }.compactMap { entry in
                historyItem(entry, store: store, openInCurrentTab: openInCurrentTab, open: open).map {
                    PageCandidate(
                        item: $0,
                        title: entry.title,
                        address: URL(string: entry.url)?.displayAddress ?? entry.url,
                        bonus: frecency(visitCount: entry.visitCount, lastVisit: entry.lastVisit)
                    )
                }
            }
        let items = mostRelevant(candidates, for: query, limit: limit) { ($0.title, $0.address, $0.bonus) }
            .map(\.item)

        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "pages", title: String(localized: "Pages"), items: items)
    }

    static let openTabBonus = 120

    private struct PageCandidate {
        let item: OmniboxItem
        let title: String
        let address: String
        let bonus: Int
    }

    static func tabItem(_ tab: BrowserTab, id: String? = nil, switchTo: @escaping (BrowserTab) -> Void) -> OmniboxItem {
        let host = URL(string: tab.urlString)?.displayHost
        return OmniboxItem(
            id: id ?? "omnibox-tab-\(tab.id)",
            kind: .tab,
            title: tab.title,
            detail: [host, String(localized: "Opened Tab")].compactMap { $0 }.joined(separator: " · "),
            iconHost: host,
            completionText: tab.urlString
        ) {
            switchTo(tab)
        }
    }

    static func historyItem(
        _ entry: HistoryStore.Entry,
        id: String? = nil,
        store: HistoryStore,
        openInCurrentTab: ((URL) -> Void)?,
        open: @escaping (URL) -> Void
    ) -> OmniboxItem? {
        guard let url = URL(string: entry.url) else { return nil }
        return OmniboxItem(
            id: id ?? "omnibox-history-\(entry.id)",
            kind: .history,
            title: entry.title,
            detail: url.displayAddress ?? url.displayHost ?? entry.url,
            iconHost: url.displayHost,
            completionText: url.absoluteString,
            alternate: openInCurrentTab.map { openCurrent in { openCurrent(url) } },
            remove: { store.remove(entry) }
        ) {
            open(url)
        }
    }

    static func archivedSection(
        query: String,
        entries: [TabArchive.Entry],
        excluding openURLs: Set<String> = [],
        restore: @escaping (TabArchive.Entry) -> Void,
        remove: ((TabArchive.Entry) -> Void)? = nil
    ) -> OmniboxSection? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = query.lowercased()

        let closed = entries.filter { !openURLs.contains($0.url) }
        let listed = needle.isEmpty
            ? closed
            : mostRelevant(
                closed.filter { $0.title.lowercased().contains(needle) || $0.url.lowercased().contains(needle) },
                for: query,
                limit: closed.count
            ) {
                ($0.title, URL(string: $0.url)?.displayAddress ?? $0.url, 0)
            }
        let items: [OmniboxItem] = listed.map { entry in
            let host = URL(string: entry.url)?.displayHost
            let archived = entry.archivedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
            return OmniboxItem(
                id: "omnibox-archived-\(entry.id)",
                kind: .archived,
                title: entry.title,
                detail: [host, archived].compactMap { $0 }.joined(separator: " · "),
                iconHost: host,
                completionText: entry.url,
                remove: remove.map { remove in { remove(entry) } }
            ) {
                restore(entry)
            }
        }

        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "archived", title: String(localized: "Archived Tabs"), items: items)
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

    static func frecency(visitCount: Int, lastVisit: Date, now: Date = Date()) -> Int {
        guard visitCount > 0 else { return 0 }
        let days = max(0, now.timeIntervalSince(lastVisit)) / 86_400
        let decay: Double = switch days {
        case ..<4:
            1
        case ..<14:
            0.7
        case ..<31:
            0.5
        case ..<90:
            0.3
        default:
            0.1
        }
        return Int(log2(Double(visitCount) + 1) * 60 * decay)
    }

    private static func mostRelevant<T>(
        _ candidates: [T],
        for query: String,
        limit: Int,
        fields: (T) -> (title: String, address: String, bonus: Int)
    ) -> [T] {
        candidates.enumerated()
            .map { entry -> (index: Int, item: T, score: Int) in
                let (title, address, bonus) = fields(entry.element)
                return (
                    entry.offset,
                    entry.element,
                    relevance(title: title, address: address, for: query) + bonus
                )
            }
            .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
            .prefix(limit)
            .map(\.item)
    }

    private static func phraseItems(
        _ phrases: some Sequence<String>,
        openInNewTab: ((URL) -> Void)? = nil,
        openInCurrentTab: ((URL) -> Void)? = nil,
        settings: BrowserSettings = .shared,
        open: @escaping (URL) -> Void
    ) -> [OmniboxItem] {
        guard !isAgentOnly(settings: settings) else { return [] }
        return phrases.map { phrase in
            let search = SearchURLBuilder.searchURL(for: phrase, settings: settings)
            return OmniboxItem(
                id: "omnibox-phrase-\(phrase)",
                kind: .phrase,
                title: phrase,
                alternate: openInCurrentTab.map { openCurrent in { openCurrent(search) } }
                    ?? openInNewTab.map { openNew in { openNew(search) } }
            ) {
                open(search)
            }
        }
    }
}
