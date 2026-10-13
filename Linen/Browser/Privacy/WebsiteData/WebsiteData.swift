// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum WebsiteData {
    enum Facet: String, CaseIterable, Identifiable, Hashable, Sendable {
        case cookies
        case storage
        case serviceWorkers
        case cache

        var id: String {
            rawValue
        }

        var label: LocalizedStringResource {
            switch self {
            case .cookies:
                "Cookies"
            case .storage:
                "Local storage"
            case .serviceWorkers:
                "Background scripts"
            case .cache:
                "Cached files"
            }
        }

        var listName: LocalizedStringResource {
            switch self {
            case .cookies:
                "cookies"
            case .storage:
                "local storage"
            case .serviceWorkers:
                "background scripts"
            case .cache:
                "cached files"
            }
        }

        var types: Set<String> {
            switch self {
            case .cookies:
                [WKWebsiteDataTypeCookies]
            case .storage:
                [
                    WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage,
                    WKWebsiteDataTypeIndexedDBDatabases,
                    WKWebsiteDataTypeWebSQLDatabases,
                ]
            case .serviceWorkers:
                [WKWebsiteDataTypeServiceWorkerRegistrations]
            case .cache:
                [
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                    WKWebsiteDataTypeFetchCache,
                    WKWebsiteDataTypeOfflineWebApplicationCache,
                ]
            }
        }

        static func facets(in types: Set<String>) -> [Facet] {
            allCases.filter { !$0.types.isDisjoint(with: types) }
        }
    }

    static let allTypes: Set<String> = Facet.allCases.reduce(into: Set<String>()) {
        $0.formUnion($1.types)
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let displayName: String
        let types: Set<String>

        var id: String {
            displayName
        }

        var facets: [Facet] {
            Facet.facets(in: types)
        }

        var summary: String {
            facets
                .map { String(localized: $0.listName) }
                .formatted(.list(type: .and, width: .narrow))
        }
    }

    static func entries(in store: WKWebsiteDataStore) async -> [Entry] {
        await store.dataRecords(ofTypes: allTypes)
            .map { Entry(displayName: $0.displayName, types: $0.dataTypes) }
            .filter { !$0.facets.isEmpty }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func remove(_ names: Set<String>, from store: WKWebsiteDataStore) async {
        guard !names.isEmpty else { return }
        let records = await store.dataRecords(ofTypes: allTypes)
            .filter { names.contains($0.displayName) }
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: allTypes, for: records)
    }

    static func matches(_ entry: Entry, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        let name = entry.displayName.lowercased()
        return name.hasPrefix(needle)
            || name.split(separator: ".").contains { $0.hasPrefix(needle) }
    }
}
