// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated struct SearchHit: Sendable {
    let title: String
    let url: String
    let snippet: String
}

nonisolated enum SnippetFetcher {
    static func search(query: String, limit: Int = 3) async -> [SearchHit] {
        for source in Source.allCases {
            let hits = await fetch(query: query, limit: limit, from: source)
            if !hits.isEmpty {
                return hits
            }
            Pipeline.log.notice("search: \(source.rawValue, privacy: .public) returned nothing")
        }
        return []
    }

    enum Source: String, CaseIterable {
        case html
        case lite

        var endpoint: String {
            switch self {
            case .html:
                "https://html.duckduckgo.com/html/"
            case .lite:
                "https://lite.duckduckgo.com/lite/"
            }
        }
    }

    private static func fetch(query: String, limit: Int, from source: Source) async -> [SearchHit] {
        var components = URLComponents(string: source.endpoint)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: components.url!, timeoutInterval: 4)
        request.setValue(WebViewPool.safariUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return [] }

        return switch source {
        case .html:
            hits(in: html, limit: limit)
        case .lite:
            liteHits(in: html, limit: limit)
        }
    }

    static func liteHits(in html: String, limit: Int) -> [SearchHit] {
        var results: [SearchHit] = []
        var remainder = html[html.startIndex...]

        while results.count < limit,
              let tag = remainder.range(
                  of: #"<a[^>]*class=['"]result-link['"][^>]*>"#,
                  options: .regularExpression
              ) ?? remainder.range(
                  of: #"<a[^>]*class=['"]result-link['"][^>]*>"#,
                  options: [.regularExpression, .caseInsensitive]
              ) {
            let openingTag = String(remainder[tag])
            let afterTag = remainder[tag.upperBound...]
            guard let titleClose = afterTag.range(of: "</a>") else { break }
            let title = clean(String(afterTag[..<titleClose.lowerBound]))
            let rawHref = attribute("href", in: openingTag) ?? ""

            var snippet = ""
            if let snippetStart = afterTag.range(
                of: #"class=['"]result-snippet['"][^>]*>"#,
                options: .regularExpression
            ), let snippetEnd = afterTag[snippetStart.upperBound...].range(of: "</td>") {
                snippet = clean(String(afterTag[snippetStart.upperBound..<snippetEnd.lowerBound]))
            }

            let destination = realURL(fromDuckDuckGoHref: rawHref)
            if !title.isEmpty, !rawHref.isEmpty,
               !isAdvertisement(href: rawHref), destination.count <= 300 {
                results.append(SearchHit(
                    title: truncate(title, to: 80),
                    url: destination,
                    snippet: truncate(snippet, to: 160)
                ))
            }
            remainder = afterTag[titleClose.upperBound...]
        }
        return results
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let match = tag.range(
            of: "\(name)=['\"][^'\"]*['\"]",
            options: .regularExpression
        ) else { return nil }
        let assignment = tag[match]
        guard let open = assignment.firstIndex(where: { $0 == "\"" || $0 == "'" }),
              let close = assignment.lastIndex(where: { $0 == "\"" || $0 == "'" }),
              open < close
        else { return nil }
        return String(assignment[assignment.index(after: open)..<close])
    }

    static func isAdvertisement(href: String) -> Bool {
        href.contains("/y.js") || href.contains("ad_provider=") || href.contains("ad_domain=")
    }

    static func hits(in html: String, limit: Int) -> [SearchHit] {
        var results: [SearchHit] = []
        var remainder = html[html.startIndex...]

        while results.count < limit,
              let titleStart = remainder.range(of: #"<a[^>]*class="result__a"[^>]*href=""#, options: .regularExpression) {
            let afterHref = remainder[titleStart.upperBound...]
            guard let hrefEnd = afterHref.range(of: "\"") else { break }
            let rawHref = String(afterHref[..<hrefEnd.lowerBound])

            guard let titleTagEnd = afterHref.range(of: ">"),
                  let titleClose = afterHref[titleTagEnd.upperBound...].range(of: "</a>")
            else { break }
            let title = clean(String(afterHref[titleTagEnd.upperBound..<titleClose.lowerBound]))

            var snippet = ""
            if let snippetStart = afterHref.range(of: #"class="result__snippet"[^>]*>"#, options: .regularExpression),
               let snippetEnd = afterHref[snippetStart.upperBound...].range(of: "</a>") {
                snippet = clean(String(afterHref[snippetStart.upperBound..<snippetEnd.lowerBound]))
            }

            let destination = realURL(fromDuckDuckGoHref: rawHref)
            if !title.isEmpty, !isAdvertisement(href: rawHref), destination.count <= 300 {
                results.append(SearchHit(
                    title: truncate(title, to: 80),
                    url: destination,
                    snippet: truncate(snippet, to: 160)
                ))
            }
            remainder = afterHref[titleClose.upperBound...]
        }
        return results
    }

    private static func realURL(fromDuckDuckGoHref href: String) -> String {
        let unescaped = href.replacingOccurrences(of: "&amp;", with: "&")
        let absolute = unescaped.hasPrefix("//") ? "https:" + unescaped : unescaped
        guard let components = URLComponents(string: absolute),
              let encoded = components.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return absolute }
        return encoded
    }

    private static func truncate(_ text: String, to maxLength: Int) -> String {
        text.count <= maxLength ? text : String(text.prefix(maxLength)) + "…"
    }

    private static func clean(_ fragment: String) -> String {
        fragment
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
