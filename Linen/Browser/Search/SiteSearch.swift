// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum SiteSearch {
    static let catalog: [SearchEngine] = [
        SearchEngine(id: "youtube", name: "YouTube", template: "https://www.youtube.com/results?search_query=%s"),
        SearchEngine(id: "reddit", name: "Reddit", template: "https://www.reddit.com/search/?q=%s"),
        SearchEngine(id: "github", name: "GitHub", template: "https://github.com/search?q=%s"),
        SearchEngine(id: "amazon", name: "Amazon", template: "https://www.amazon.com/s?k=%s"),
    ] + SearchEngine.catalog

    static func match(_ query: String, customEngine: SearchEngine? = nil) -> SearchEngine? {
        var prefix = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where prefix.hasPrefix(scheme) {
            prefix = String(prefix.dropFirst(scheme.count))
        }
        if prefix.hasPrefix("www.") {
            prefix = String(prefix.dropFirst(4))
        }
        if prefix.hasSuffix("/") {
            prefix.removeLast()
        }
        guard prefix.count >= 2 else { return nil }

        var engines = catalog
        if let customEngine, customEngine.isCustom, customEngine.searchURL(for: "test") != nil {
            engines.insert(customEngine, at: 0)
        }
        return engines.first { aliases(for: $0).contains(prefix) }
            ?? engines.first { aliases(for: $0).contains { $0.hasPrefix(prefix) } }
    }

    private static func aliases(for engine: SearchEngine) -> [String] {
        var aliases = [engine.id, engine.name.lowercased()]
        if let host = engine.host?.lowercased() {
            aliases.append(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
        }
        return aliases
    }
}
