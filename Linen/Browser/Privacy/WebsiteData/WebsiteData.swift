// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum WebsiteData {
    nonisolated enum Facet: String, CaseIterable, Identifiable, Hashable, Sendable {
        case cookies
        case storage
        case serviceWorkers
        case cache

        var id: String {
            rawValue
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

    nonisolated static let allTypes: Set<String> = Facet.allCases.reduce(into: Set<String>()) {
        $0.formUnion($1.types)
    }

    nonisolated struct Entry: Identifiable, Equatable, Sendable {
        let displayName: String
        let types: Set<String>
        let facets: [Facet]
        let summary: String

        init(displayName: String, types: Set<String>) {
            self.displayName = displayName
            self.types = types
            facets = Facet.facets(in: types)
            summary = facets
                .map { String(localized: $0.listName) }
                .formatted(.list(type: .and, width: .narrow))
        }

        var id: String {
            displayName
        }
    }

    nonisolated struct RecordSummary: Sendable {
        let displayName: String
        let types: Set<String>
    }

    struct Snapshot {
        let entries: [Entry]
        fileprivate let records: [String: [WKWebsiteDataRecord]]

        func removing(_ names: Set<String>) -> Snapshot {
            Snapshot(
                entries: entries.filter { !names.contains($0.displayName) },
                records: records.filter { !names.contains($0.key) }
            )
        }
    }

    @concurrent
    nonisolated static func entries(from records: [RecordSummary]) async -> [Entry] {
        records
            .map { Entry(displayName: $0.displayName, types: $0.types) }
            .filter { !$0.facets.isEmpty }
            .map { ($0, $0.displayName) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map(\.0)
    }

    static func snapshot(of store: WKWebsiteDataStore) async -> Snapshot {
        let records = await store.dataRecords(ofTypes: allTypes)
        let summaries = records.map { RecordSummary(displayName: $0.displayName, types: $0.dataTypes) }
        return Snapshot(
            entries: await entries(from: summaries),
            records: Dictionary(grouping: records, by: \.displayName)
        )
    }

    static func remove(_ names: Set<String>, of snapshot: Snapshot, from store: WKWebsiteDataStore) async {
        let records = names.flatMap { snapshot.records[$0] ?? [] }
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: allTypes, for: records)
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
