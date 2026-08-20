// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SQLite3

enum BrowserImport {
    struct Summary {
        var pages = 0
        var bookmarks = 0

        var isEmpty: Bool {
            pages == 0 && bookmarks == 0
        }

        var phrase: String {
            [
                pages > 0 ? String(localized: "\(pages) pages of history") : nil,
                bookmarks > 0 ? String(localized: "\(bookmarks) bookmarks") : nil,
            ]
            .compactMap { $0 }
            .formatted(.list(type: .and))
        }
    }

    struct Payload: Sendable {
        var pages: [HistoryStore.Entry] = []
        var bookmarks: [HistoryStore.Entry] = []
        var folderName = ""

        var summary: Summary {
            Summary(pages: pages.count, bookmarks: bookmarks.count)
        }
    }

    enum Failure: Error {
        case notInstalled
        case needsFullDiskAccess
    }

    nonisolated enum Source: String, Hashable, Sendable, CaseIterable {
        case safari, chrome

        var name: String {
            self == .safari ? "Safari" : "Chrome"
        }

        var isPresent: Bool {
            self == .safari ? BrowserImport.safariIsPresent : BrowserImport.chromeIsPresent
        }

        var caption: LocalizedStringResource {
            switch self {
            case .safari:
                "Bookmarks and history."
            case .chrome:
                isPresent ? "Bookmarks and history, from every profile." : "Not on this Mac."
            }
        }

        func scan() throws -> Payload {
            switch self {
            case .safari:
                try BrowserImport.scanSafari()
            case .chrome:
                try BrowserImport.scanChrome()
            }
        }
    }

    // MARK: - Sources

    nonisolated static var chromeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Google/Chrome")
    }

    nonisolated static var safariDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari")
    }

    nonisolated static var chromeIsPresent: Bool {
        FileManager.default.fileExists(atPath: chromeDirectory.path)
    }

    nonisolated static var safariIsPresent: Bool {
        FileManager.default.fileExists(atPath: safariDirectory.path)
    }

    // MARK: - Chrome

    nonisolated static func scanChrome() throws -> Payload {
        guard chromeIsPresent else { throw Failure.notInstalled }
        var payload = Payload(folderName: "Chrome Bookmarks")

        for profile in chromeProfiles() {
            if let data = try? Data(contentsOf: profile.appending(path: "Bookmarks")) {
                payload.bookmarks += chromeBookmarks(from: data)
            }
            if let copy = try? copyDatabase(profile.appending(path: "History")) {
                defer { discardCopy(copy) }
                payload.pages += chromeHistoryRows(in: copy)
            }
        }
        return payload
    }

    private nonisolated static func chromeProfiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: chromeDirectory.path)) ?? []
        return names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { chromeDirectory.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "History").path) }
    }

    nonisolated static func chromeBookmarks(from data: Data) -> [HistoryStore.Entry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any]
        else { return [] }
        var found: [HistoryStore.Entry] = []
        for case let root as [String: Any] in roots.values {
            collectChromeBookmarks(root, into: &found)
        }
        return found
    }

    private nonisolated static func collectChromeBookmarks(
        _ node: [String: Any],
        into found: inout [HistoryStore.Entry]
    ) {
        if node["type"] as? String == "url", let url = node["url"] as? String {
            found.append(HistoryStore.Entry(
                url: url,
                title: node["name"] as? String ?? url,
                date: chromeDate((node["date_added"] as? String).flatMap(Double.init) ?? 0)
            ))
            return
        }
        for case let child as [String: Any] in node["children"] as? [Any] ?? [] {
            collectChromeBookmarks(child, into: &found)
        }
    }

    nonisolated static func chromeDate(_ micros: Double) -> Date {
        guard micros > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: micros / 1_000_000 - 11_644_473_600)
    }

    private nonisolated static func chromeHistoryRows(in database: URL) -> [HistoryStore.Entry] {
        query(
            database,
            sql: "SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 3000"
        ) { url, title, stamp in
            HistoryStore.Entry(url: url, title: title.isEmpty ? url : title, date: chromeDate(stamp))
        }
    }

    // MARK: - Safari

    nonisolated static func scanSafari() throws -> Payload {
        guard safariIsPresent else { throw Failure.notInstalled }
        let bookmarksFile = safariDirectory.appending(path: "Bookmarks.plist")
        guard FileManager.default.isReadableFile(atPath: bookmarksFile.path) else {
            throw Failure.needsFullDiskAccess
        }

        var payload = Payload(folderName: "Safari Bookmarks")

        if let data = try? Data(contentsOf: bookmarksFile) {
            payload.bookmarks = safariBookmarks(from: data)
        }
        if let copy = try? copyDatabase(safariDirectory.appending(path: "History.db")) {
            defer { discardCopy(copy) }
            payload.pages = safariHistoryRows(in: copy)
        }
        return payload
    }

    // MARK: - Applying

    @MainActor
    static func apply(_ payload: Payload, into browser: BrowserModel) {
        browser.history.merge(payload.pages)
        browser.importBookmarksFolder(named: payload.folderName, entries: payload.bookmarks)
    }

    nonisolated static func safariBookmarks(from data: Data) -> [HistoryStore.Entry] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any]
        else { return [] }
        var found: [HistoryStore.Entry] = []
        collectSafariBookmarks(root, into: &found)
        return found
    }

    private nonisolated static func collectSafariBookmarks(
        _ node: [String: Any],
        into found: inout [HistoryStore.Entry]
    ) {
        if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
           let url = node["URLString"] as? String {
            let uri = node["URIDictionary"] as? [String: Any]
            found.append(HistoryStore.Entry(
                url: url,
                title: uri?["title"] as? String ?? url,
                date: .distantPast
            ))
            return
        }
        for case let child as [String: Any] in node["Children"] as? [Any] ?? [] {
            collectSafariBookmarks(child, into: &found)
        }
    }

    nonisolated static func safariDate(_ seconds: Double) -> Date {
        guard seconds > 0 else { return .distantPast }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private nonisolated static func safariHistoryRows(in database: URL) -> [HistoryStore.Entry] {
        query(
            database,
            sql: """
            SELECT i.url, IFNULL(MAX(v.title), ''), MAX(v.visit_time)
            FROM history_items i JOIN history_visits v ON v.history_item = i.id
            GROUP BY i.id ORDER BY 3 DESC LIMIT 3000
            """
        ) { url, title, stamp in
            HistoryStore.Entry(url: url, title: title.isEmpty ? url : title, date: safariDate(stamp))
        }
    }

    // MARK: - Test seams

    nonisolated static func testHistoryRows(chrome database: URL) -> [HistoryStore.Entry] {
        chromeHistoryRows(in: database)
    }

    nonisolated static func testHistoryRows(safari database: URL) -> [HistoryStore.Entry] {
        safariHistoryRows(in: database)
    }

    // MARK: - Reading a database that belongs to someone else

    private nonisolated static func copyDatabase(_ source: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "linen-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let destination = staging.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] {
            let sidecar = source.deletingLastPathComponent()
                .appending(path: source.lastPathComponent + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try? FileManager.default.copyItem(
                    at: sidecar,
                    to: staging.appending(path: destination.lastPathComponent + suffix)
                )
            }
        }
        return destination
    }

    private nonisolated static func discardCopy(_ database: URL) {
        try? FileManager.default.removeItem(at: database.deletingLastPathComponent())
    }

    private nonisolated static func query(
        _ database: URL,
        sql: String,
        row: (String, String, Double) -> HistoryStore.Entry
    ) -> [HistoryStore.Entry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var results: [HistoryStore.Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            guard !url.isEmpty else { continue }
            results.append(row(url, title, sqlite3_column_double(statement, 2)))
        }
        return results
    }
}
