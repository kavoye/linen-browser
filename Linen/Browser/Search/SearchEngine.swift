// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct SearchEngine: Identifiable, Hashable, Sendable {
    enum SuggestionFormat: Hashable {
        case phrases
        case openSearch
    }

    static let customID = "custom"

    let id: String
    let name: String
    let template: String
    let suggestTemplate: String?
    let suggestionFormat: SuggestionFormat
    init(
        id: String,
        name: String,
        template: String,
        suggestTemplate: String? = nil,
        suggestionFormat: SuggestionFormat = .openSearch
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.suggestTemplate = suggestTemplate
        self.suggestionFormat = suggestionFormat
    }

    var isCustom: Bool {
        id == Self.customID
    }

    var host: String? {
        URLComponents(string: template.replacingOccurrences(of: "%s", with: "q"))?.host
    }

    func searchURL(for query: String) -> URL? {
        Self.expand(template, with: query)
    }

    func suggestURL(for query: String) -> URL? {
        guard let suggestTemplate else { return nil }
        return Self.expand(suggestTemplate, with: query)
    }

    private static func expand(_ template: String, with query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }

        let filled = template.contains("%s")
            ? template.replacingOccurrences(of: "%s", with: escaped)
            : template.trimmingCharacters(in: .whitespaces) + escaped

        guard let url = URL(string: filled),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host()?.contains(".") == true
        else { return nil }
        return url
    }

    static func custom(name: String, template: String) -> SearchEngine {
        SearchEngine(
            id: customID,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom" : name,
            template: template
        )
    }

    // MARK: - The list

    static let duckDuckGo = SearchEngine(
        id: "duckduckgo",
        name: "DuckDuckGo",
        template: "https://duckduckgo.com/?q=%s",
        suggestTemplate: "https://duckduckgo.com/ac/?q=%s&kl=wt-wt",
        suggestionFormat: .phrases
    )

    static let catalog: [SearchEngine] = [
        duckDuckGo,
        SearchEngine(
            id: "google",
            name: "Google",
            template: "https://www.google.com/search?q=%s",
            suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        ),
        SearchEngine(
            id: "bing",
            name: "Bing",
            template: "https://www.bing.com/search?q=%s",
            suggestTemplate: "https://api.bing.com/osjson.aspx?query=%s"
        ),
        SearchEngine(
            id: "brave",
            name: "Brave Search",
            template: "https://search.brave.com/search?q=%s",
            suggestTemplate: "https://search.brave.com/api/suggest?q=%s"
        ),
        SearchEngine(
            id: "startpage",
            name: "Startpage",
            template: "https://www.startpage.com/sp/search?query=%s"
        ),
        SearchEngine(
            id: "ecosia",
            name: "Ecosia",
            template: "https://www.ecosia.org/search?q=%s"
        ),
        SearchEngine(
            id: "kagi",
            name: "Kagi",
            template: "https://kagi.com/search?q=%s"
        ),
        SearchEngine(
            id: "wikipedia",
            name: "Wikipedia",
            template: "https://en.wikipedia.org/w/index.php?search=%s"
        ),
    ]
}
