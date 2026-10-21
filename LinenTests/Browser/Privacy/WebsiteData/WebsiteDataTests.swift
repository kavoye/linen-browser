// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

struct WebsiteDataTests {
    private func entry(_ name: String, _ types: Set<String>) -> WebsiteData.Entry {
        WebsiteData.Entry(displayName: name, types: types)
    }

    @Test func everyFacetClaimsAtLeastOneWebKitType() {
        for facet in WebsiteData.Facet.allCases {
            #expect(!facet.types.isEmpty)
        }
    }

    @Test func noTwoFacetsClaimTheSameWebKitType() {
        var seen: Set<String> = []
        for facet in WebsiteData.Facet.allCases {
            #expect(seen.isDisjoint(with: facet.types))
            seen.formUnion(facet.types)
        }
        #expect(seen == WebsiteData.allTypes)
    }

    @Test func aRecordIsDescribedByWhatItActuallyHolds() {
        let cookiesOnly = entry("example.com", [WKWebsiteDataTypeCookies])
        #expect(cookiesOnly.facets == [.cookies])

        let mixed = entry("example.com", [WKWebsiteDataTypeCookies, WKWebsiteDataTypeDiskCache])
        #expect(mixed.facets == [.cookies, .cache])
    }

    @Test func facetsComeBackInAFixedOrder() {
        let all = entry("example.com", WebsiteData.allTypes)
        #expect(all.facets == WebsiteData.Facet.allCases)
    }

    @Test func everyStorageFlavorReadsAsLocalStorage() {
        for type in [
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
        ] {
            #expect(entry("example.com", [type]).facets == [.storage])
        }
    }

    @Test func aRecordWeCannotDescribeHasNoFacets() {
        #expect(entry("example.com", ["com.example.somethingElse"]).facets.isEmpty)
    }

    @Test func theSummaryNamesEveryFacetMidSentence() {
        let summary = entry("example.com", [WKWebsiteDataTypeCookies, WKWebsiteDataTypeDiskCache]).summary
        #expect(summary.contains("cookies"))
        #expect(summary.contains("cached files"))
    }

    @Test func searchMatchesTheStartOfANameOrOfAnyPartOfIt() {
        let github = entry("github.com", [WKWebsiteDataTypeCookies])
        #expect(WebsiteData.matches(github, query: "git"))
        #expect(WebsiteData.matches(github, query: "GITHUB"))
        #expect(WebsiteData.matches(github, query: "com"))
        #expect(!WebsiteData.matches(github, query: "figma"))

        let subdomain = entry("avatars.githubusercontent.com", [WKWebsiteDataTypeCookies])
        #expect(WebsiteData.matches(subdomain, query: "git"))
    }

    @Test func searchDoesNotMatchMidWord() {
        let digitalgov = entry("digitalgov.gov", [WKWebsiteDataTypeCookies])
        #expect(!WebsiteData.matches(digitalgov, query: "git"))
        #expect(WebsiteData.matches(digitalgov, query: "digital"))
    }

    @Test func anEmptyQueryMatchesEverything() {
        let github = entry("github.com", [WKWebsiteDataTypeCookies])
        #expect(WebsiteData.matches(github, query: ""))
        #expect(WebsiteData.matches(github, query: "   "))
    }

    @Test func theListKeepsDescribableSitesInNameOrder() async {
        let entries = await WebsiteData.entries(from: [
            .init(displayName: "zeta.com", types: [WKWebsiteDataTypeCookies]),
            .init(displayName: "Alpha.com", types: [WKWebsiteDataTypeDiskCache]),
            .init(displayName: "odd.com", types: ["com.example.somethingElse"]),
        ])
        #expect(entries.map(\.displayName) == ["Alpha.com", "zeta.com"])
        #expect(entries.first?.summary.contains("cached files") == true)
    }

    @MainActor
    @Test func removingASiteDropsOnlyItsRowWithoutCountingAgain() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        for host in ["keep.example", "drop.example"] {
            let cookie = try #require(HTTPCookie(properties: [
                .domain: host, .path: "/", .name: "session", .value: "1",
            ]))
            await store.httpCookieStore.setCookie(cookie)
        }
        let snapshot = await WebsiteData.snapshot(of: store)
        #expect(snapshot.entries.map(\.displayName) == ["drop.example", "keep.example"])

        await WebsiteData.remove(["drop.example"], of: snapshot, from: store)
        #expect(snapshot.removing(["drop.example"]).entries.map(\.displayName) == ["keep.example"])
        #expect(await WebsiteData.snapshot(of: store).entries.map(\.displayName) == ["keep.example"])
    }
}
