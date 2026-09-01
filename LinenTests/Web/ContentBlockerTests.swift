// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The rules the browser blocks with. WebKit compiles these, so a mistake in
/// the JSON is a silent no-op rather than an error - hence the shape being
/// pinned here rather than trusted.
struct ContentBlockerRuleTests {
    private func rules(exempt: Set<String> = []) throws -> [[String: Any]] {
        let json = try #require(ContentBlocker.rulesJSON(exemptHosts: exempt))
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func everyTrackerBecomesABlockRule() throws {
        let parsed = try rules()
        #expect(parsed.count == TrackerList.domains.count + 1)
        for rule in parsed.prefix(TrackerList.domains.count) {
            let action = try #require(rule["action"] as? [String: Any])
            #expect(action["type"] as? String == "block")
        }
    }

    /// A site serving its own analytics from its own domain is not what this
    /// is for, and blocking it breaks pages for no privacy gain.
    @Test func onlyThirdPartyLoadsAreBlocked() throws {
        for rule in try rules().prefix(TrackerList.domains.count) {
            let trigger = try #require(rule["trigger"] as? [String: Any])
            #expect(trigger["load-type"] as? [String] == ["third-party"])
        }
    }

    @Test func topFrameNavigationIsNeverBlocked() throws {
        let rule = try #require(try rules().last)

        let action = try #require(rule["action"] as? [String: Any])
        #expect(action["type"] as? String == "ignore-previous-rules")

        let trigger = try #require(rule["trigger"] as? [String: Any])
        #expect(trigger["resource-type"] as? [String] == ["document"])
        #expect(trigger["load-context"] as? [String] == ["top-frame"])
    }

    /// The filter is a regex WebKit runs against the whole URL, so an
    /// unescaped dot matches any character and the anchor is what stops a
    /// tracker's name in some other URL's query counting as a hit.
    @Test func aFilterIsAnchoredAndEscaped() {
        let filter = TrackerList.filter(for: "google-analytics.com")
        #expect(filter.hasPrefix("^https?://"))
        #expect(filter.contains("google-analytics\\.com"))
        #expect(!filter.contains("google-analytics.com"))
    }

    /// Subdomains count - `ssl.google-analytics.com` is the same tracker.
    @Test func aFilterMatchesSubdomains() throws {
        let filter = TrackerList.filter(for: "example.com")
        let regex = try NSRegularExpression(pattern: filter)

        for url in [
            "https://example.com/beacon",
            "https://ssl.example.com/beacon",
            "http://a.b.example.com/",
        ] {
            let range = NSRange(url.startIndex..., in: url)
            #expect(regex.firstMatch(in: url, range: range) != nil, "should match \(url)")
        }
    }

    /// The two cases that would make the list overreach: a different domain
    /// that merely ends the same way, and the name appearing in a query.
    @Test func aFilterDoesNotMatchLookalikes() throws {
        let filter = TrackerList.filter(for: "example.com")
        let regex = try NSRegularExpression(pattern: filter)

        for url in [
            "https://notexample.com/",
            "https://safe.test/?ref=https://example.com",
        ] {
            let range = NSRange(url.startIndex..., in: url)
            #expect(regex.firstMatch(in: url, range: range) == nil, "should not match \(url)")
        }
    }

    /// An entry naming one endpoint must not take the whole domain with it.
    @Test func anEntryWithAPathKeepsIt() throws {
        let filter = TrackerList.filter(for: "facebook.com/tr")
        let regex = try NSRegularExpression(pattern: filter)

        let tracker = "https://www.facebook.com/tr?id=1"
        #expect(regex.firstMatch(in: tracker, range: NSRange(tracker.startIndex..., in: tracker)) != nil)

        let ordinary = "https://www.facebook.com/some/page"
        #expect(regex.firstMatch(in: ordinary, range: NSRange(ordinary.startIndex..., in: ordinary)) == nil)
    }

    /// WebKit applies rules in order and `ignore-previous-rules` undoes every
    /// match before it, so an exception placed anywhere but last would switch
    /// blocking off for the rules that follow it.
    @Test func anExceptionIsTheLastRule() throws {
        let parsed = try rules(exempt: ["example.com"])
        #expect(parsed.count == TrackerList.domains.count + 2)

        let last = try #require(parsed.last)
        let action = try #require(last["action"] as? [String: Any])
        #expect(action["type"] as? String == "ignore-previous-rules")

        // `if-domain` is the page being looked at, which is what a per-website
        // exception means.
        let trigger = try #require(last["trigger"] as? [String: Any])
        #expect(trigger["if-domain"] as? [String] == ["*example.com"])
    }

    @Test func noExceptionsMeansNoExceptionRule() throws {
        #expect(try rules().count == TrackerList.domains.count + 1)
    }

    @Test func hostsAreNormalizedSoWwwIsNotASeparateWebsite() {
        #expect(ContentBlocker.normalized("WWW.Example.COM") == "example.com")
        #expect(ContentBlocker.normalized("news.example.com") == "news.example.com")
    }

    /// A duplicate would compile to two identical rules and read as two
    /// entries in a list the user never sees.
    @Test func theTrackerListHasNoDuplicates() {
        #expect(Set(TrackerList.domains).count == TrackerList.domains.count)
    }

    /// WebKit rejects a rule list it cannot compile, and the failure is a log
    /// line rather than anything the user sees - so the real compiler is what
    /// this has to be checked against.
    @Test func webKitCompilesTheRules() async throws {
        let json = try #require(ContentBlocker.rulesJSON(exemptHosts: ["example.com"]))
        let store = try #require(WKContentRuleListStore.default())
        let compiled = try await store.compileContentRuleList(
            forIdentifier: "Linen.trackers.test",
            encodedContentRuleList: json
        )
        #expect(compiled != nil)
        try? await store.removeContentRuleList(forIdentifier: "Linen.trackers.test")
    }
}
