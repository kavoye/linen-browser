// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct AgentSearchTests {
    @Test func searchBatchesQueriesFiltersDomainsAndCachesWithinATask() async {
        var requested: [String] = []
        let browser = BrowserModel(database: .temporary())
        let tab = browser.newTab()
        let originalURL = tab.urlString
        let toolkit = AgentToolkit(
            browser: browser, media: MediaCenter(), log: ConversationLog(database: .temporary()),
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
        #expect(browser.activeTab === tab)
        #expect(tab.urlString == originalURL)
        _ = await toolkit.searchWeb(query: "first", domain: "example.com")
        #expect(requested.count == 2)
        toolkit.beginTask(AgentTaskContext(id: UUID(), tabID: tab.id))
        _ = await toolkit.searchWeb(query: "first", domain: "example.com")
        #expect(requested.count == 3)
    }

    @Test(.boundedWebViews, arguments: [false, true])
    func searchingPreservesTheFormAndCalendarObservation(noResults: Bool) async throws {
        var services = AgentToolkit.Services.live
        services.search = { _ in noResults ? [] : [SearchHit(title: "Support", url: "https://example.com/help", snippet: "Booking information")] }
        let fixture = try await ComputerWorkflowFixture(services: services)
        defer { fixture.close() }
        let view = fixture.tab.webView
        _ = try await view.evaluateJavaScript("""
            document.querySelector('#query').value='Lviv';
            document.body.insertAdjacentHTML('beforeend', '<input id="date" aria-label="Departure date" readonly value="September 23">'
              + '<div role="gridcell" tabindex="0" id="day" style="position:absolute;left:20px;top:280px;width:44px;height:32px">29</div>');
            document.querySelector('#day').addEventListener('click', () => document.querySelector('#date').value='September 29');
            """)
        let url = view.url
        _ = await fixture.toolkit.readPage()
        let before = try #require(PageDriver.observation(in: view))
        _ = await fixture.toolkit.searchWeb(query: "rail booking window")
        #expect(view.url == url)
        #expect(fixture.tab.urlString == url?.absoluteString)
        #expect(try await view.evaluateJavaScript("document.querySelector('#query').value") as? String == "Lviv")
        let result = try await ClickOnPageTool(toolkit: fixture.toolkit).call(arguments: .init(
            page: fixture.tab.id.uuidString, observationID: before.id, ref: 0, label: "29"))
        #expect(result.contains("Clicked"))
        #expect(try await view.evaluateJavaScript("document.querySelector('#date').value") as? String == "September 29")
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
