// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum SearchURLBuilder {
    static var engine: SearchEngine {
        let chosen = BrowserSettings.shared.searchEngine
        return chosen.searchURL(for: "test") == nil ? SearchEngine.duckDuckGo : chosen
    }

    static func searchURL(for query: String) -> URL {
        engine.searchURL(for: query) ?? SearchEngine.duckDuckGo.searchURL(for: query)!
    }

}

enum SearchEngineHosts {
    private static let domains: Set<String> = [
        "duckduckgo.com",
        "bing.com",
        "ecosia.org",
        "kagi.com",
        "startpage.com",
        "qwant.com",
        "mojeek.com",
        "baidu.com",
        "ask.com",
        "you.com",
        "perplexity.ai",
    ]

    private static let hosts: Set<String> = [
        "search.brave.com",
        "search.yahoo.com",
        "search.aol.com",
        "searx.be",
        "search.marginalia.nu",
    ]

    static func isSearchEngine(_ host: String) -> Bool {
        let host = host.lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if hosts.contains(bare) {
            return true
        }
        if domains.contains(where: { bare == $0 || bare.hasSuffix("." + $0) }) {
            return true
        }
        if bare.split(separator: ".").first == "google" {
            return true
        }
        if let engineHost = SearchURLBuilder.engine.host?.lowercased() {
            let bareEngine = engineHost.hasPrefix("www.") ? String(engineHost.dropFirst(4)) : engineHost
            if bare == bareEngine {
                return true
            }
        }
        return false
    }
}
