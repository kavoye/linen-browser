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
}
