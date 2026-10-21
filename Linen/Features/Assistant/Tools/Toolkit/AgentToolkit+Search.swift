// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func searchWeb(query: String, additionalQueries: [String] = [], domain: String = "") async -> String {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seenQueries = Set<String>()
        let queries = ([query] + additionalQueries).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seenQueries.insert($0).inserted }
        let step = beginTool(name: "searchWeb")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard (1...4).contains(queries.count), queries.allSatisfy({ $0.utf8.count <= 2048 }) else {
            let output = "Enter a search term, with at most three additional queries of up to 2,048 bytes each."
            completeTool(step, failed: true)
            return output
        }
        guard domain.isEmpty || (domain.contains(".") && domain.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil
            && URL(string: "https://" + domain)?.host() == domain) else {
            let output = "Use a domain such as example.com, without a path or URL scheme."
            completeTool(step, failed: true)
            return output
        }
        guard visibleTaskTab != nil else {
            let output = String(localized: "The active tab changed before the assistant could use it.")
            completeTool(step, failed: true)
            return output
        }
        let groups = await withTaskGroup(of: (Int, [SearchHit]).self) { group in
            for (index, term) in queries.enumerated() {
                let scoped = domain.isEmpty ? term : "site:\(domain) \(term)"
                group.addTask { (index, await self.search.hits(for: scoped)) }
            }
            var groups = Array(repeating: [SearchHit](), count: queries.count)
            for await (index, hits) in group {
                groups[index] = hits
            }
            return groups
        }
        var fetchedHits: [SearchHit] = []
        var seenURLs = Set<String>()
        for rank in 0..<6 {
            for group in groups where group.indices.contains(rank) {
                let hit = group[rank]
                guard let url = URL(string: hit.url), let host = url.host()?.lowercased(),
                      domain.isEmpty || host == domain || host.hasSuffix("." + domain),
                      seenURLs.insert(hit.url).inserted else { continue }
                fetchedHits.append(hit)
            }
        }
        if let output = cancellationOutput(for: step) {
            return output
        }
        let hits = fetchedHits.filter { hit in
            URL(string: hit.url).flatMap(Self.webURL) != nil
        }
        guard !hits.isEmpty else {
            let output = "No results (network problem or no matches)."
            completeTool(step, failed: true)
            return output
        }

        var lines: [String] = []
        for (index, hit) in hits.prefix(outputBudget.controlLimit <= 12 ? 3 : 6).enumerated() {
            let line = "\(index + 1). \(hit.title)\n   URL: \(hit.url)\n   \(hit.snippet)"
            guard PageOutputBudget.cost((lines + [line]).joined(separator: "\n")) < outputBudget.driverBudget.totalCharacters - 150 else { break }
            lines.append(line)
        }
        let output = lines.joined(separator: "\n")
        let links = hits.prefix(lines.count).compactMap { hit -> ConversationLog.ActivityLink? in
            guard let url = URL(string: hit.url) else { return nil }
            return ConversationLog.ActivityLink(title: hit.title, url: url)
        }
        remember(links: links)
        completeTool(step)
        return fencedPageOutput(output)
    }
}
