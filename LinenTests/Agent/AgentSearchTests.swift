// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentSearchTests {
    @Test func searchBatchesQueriesFiltersDomainsAndCachesWithinATask() async {
        var requested: [String] = []
        let toolkit = AgentToolkit(
            browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()),
            services: .init(search: { query in
                requested.append(query)
                let path = query.hasSuffix("first") ? "first" : "second"
                return [
                    SearchHit(title: path, url: "https://docs.example.com/\(path)", snippet: "Relevant result"),
                    SearchHit(title: "Common", url: "https://example.com/common", snippet: "Shared result"),
                    SearchHit(title: "Wrong domain", url: "https://example.com.evil.invalid/", snippet: "Excluded"),
                ]
            }, resolveVideo: { _ in ResolvedVideo(videoID: nil, fallbackURL: URL(string: "https://example.com")!) })
        )
        let result = await toolkit.searchWeb(query: "first", additionalQueries: ["second", "first"], domain: "example.com")
        #expect(Set(requested) == ["site:example.com first", "site:example.com second"])
        #expect(result.contains("docs.example.com/first"))
        #expect(result.contains("docs.example.com/second"))
        #expect(!result.contains("evil.invalid"))
        #expect(result.components(separatedBy: "https://example.com/common").count == 2)
        _ = await toolkit.searchWeb(query: "first", domain: "example.com")
        #expect(requested.count == 2)
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: UUID()))
        _ = await toolkit.searchWeb(query: "first", domain: "example.com")
        #expect(requested.count == 3)
    }

    @Test func invalidDomainAndTooManyQueriesNeverReachTheSearchProvider() async {
        var requests = 0
        let toolkit = AgentToolkit(
            browser: BrowserModel(database: .temporary()), media: MediaCenter(), log: ConversationLog(database: .temporary()),
            services: .init(search: { _ in requests += 1; return [] },
                            resolveVideo: { _ in ResolvedVideo(videoID: nil, fallbackURL: URL(string: "https://example.com")!) })
        )
        _ = await toolkit.searchWeb(query: "query", domain: "example.com/path")
        #expect(toolkit.lastToolFailed)
        _ = await toolkit.searchWeb(query: "one", additionalQueries: ["two", "three", "four", "five"])
        #expect(toolkit.lastToolFailed)
        #expect(requests == 0)
    }
}
