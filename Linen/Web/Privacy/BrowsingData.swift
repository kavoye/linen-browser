// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum BrowsingData {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case history
        case cookies
        case cache

        var id: String {
            rawValue
        }

        var label: LocalizedStringResource {
            switch self {
            case .history:
                "Browsing history"
            case .cookies:
                "Cookies and site data"
            case .cache:
                "Cached files"
            }
        }

        var caption: LocalizedStringResource {
            switch self {
            case .history:
                "Also clears your start page tiles and your conversations with the assistant."
            case .cookies:
                "Signs you out of most websites."
            case .cache:
                "Frees up space. Pages load more slowly the next time."
            }
        }

        var listName: LocalizedStringResource {
            switch self {
            case .history:
                "browsing history"
            case .cookies:
                "cookies and site data"
            case .cache:
                "cached files"
            }
        }

        var symbol: String {
            switch self {
            case .history:
                "clock"
            case .cookies:
                "checkmark.shield"
            case .cache:
                "internaldrive"
            }
        }

        var dataTypes: Set<String> {
            switch self {
            case .history:
                []
            case .cookies:
                [
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage,
                    WKWebsiteDataTypeIndexedDBDatabases,
                    WKWebsiteDataTypeWebSQLDatabases,
                    WKWebsiteDataTypeServiceWorkerRegistrations,
                ]
            case .cache:
                [
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                    WKWebsiteDataTypeFetchCache,
                    WKWebsiteDataTypeOfflineWebApplicationCache,
                ]
            }
        }
    }

    enum Range: String, CaseIterable, Identifiable, Hashable {
        case hour
        case day
        case week
        case month
        case everything

        var id: String {
            rawValue
        }

        var label: LocalizedStringResource {
            switch self {
            case .hour:
                "Last hour"
            case .day:
                "Last 24 hours"
            case .week:
                "Last 7 days"
            case .month:
                "Last 4 weeks"
            case .everything:
                "All time"
            }
        }

        var phrase: LocalizedStringResource {
            switch self {
            case .hour:
                "the last hour"
            case .day:
                "the last 24 hours"
            case .week:
                "the last 7 days"
            case .month:
                "the last 4 weeks"
            case .everything:
                "all time"
            }
        }

        var since: Date {
            switch self {
            case .hour:
                Date(timeIntervalSinceNow: -3_600)
            case .day:
                Date(timeIntervalSinceNow: -86_400)
            case .week:
                Date(timeIntervalSinceNow: -7 * 86_400)
            case .month:
                Date(timeIntervalSinceNow: -30 * 86_400)
            case .everything:
                Date(timeIntervalSince1970: 0)
            }
        }
    }

    struct ClearChoice: Equatable {
        let kinds: Set<Kind>
        let range: Range
    }

    struct ClearPrompt {
        let question: LocalizedStringResource
        let detail: LocalizedStringResource
        let kinds: Set<Kind>
        let offersKindChoice: Bool

        static let verb: LocalizedStringResource = "Clear"
        static let initialRange = Range.everything

        var ranges: [Range] {
            Range.allCases
        }

        var selectableKinds: [Kind] {
            offersKindChoice ? Kind.allCases : []
        }

        static func history() -> ClearPrompt {
            ClearPrompt(
                question: "Clear history?",
                detail: "Also clears your start page tiles.",
                kinds: [.history],
                offersKindChoice: false
            )
        }

        static func privacy() -> ClearPrompt {
            ClearPrompt(
                question: "Clear browsing data?",
                detail: "Choose what to clear and how far back to go. This can’t be undone.",
                kinds: Set(Kind.allCases),
                offersKindChoice: true
            )
        }
    }

    static func clear(
        _ kinds: Set<Kind>,
        range: Range,
        history: HistoryStore,
        agent: ConversationLog? = nil,
        tabs: [BrowserTab] = []
    ) async {
        if kinds.contains(.history) {
            if range == .everything {
                history.clear()
            } else {
                history.removeEntries(since: range.since)
            }
            agent?.clearAll()
        }

        if kinds.contains(.cookies) {
            SitePermissions.shared.removeEverything()
            for tab in tabs {
                tab.permissions.siteDataCleared()
                tab.assistantAccess.siteDataCleared()
            }
        }

        if kinds.contains(.cache) {
            FaviconLoader.shared.clear(modifiedSince: range.since)
        }

        let types = kinds.reduce(into: Set<String>()) { $0.formUnion($1.dataTypes) }
        guard !types.isEmpty else { return }
        await store.removeData(ofTypes: types, modifiedSince: range.since)
    }

    @MainActor
    static var store: WKWebsiteDataStore {
        WebViewPool.shared.dataStore
    }

    static func siteCount() async -> Int {
        let records = await store.dataRecords(ofTypes: WebsiteData.allTypes)
        return records.count
    }

    static func clearEverything(
        history: HistoryStore,
        agent: ConversationLog? = nil,
        tabs: [BrowserTab] = []
    ) async {
        await clear([.cookies, .cache], range: .everything, history: history, agent: agent, tabs: tabs)
        agent?.clearAll()
    }
}
