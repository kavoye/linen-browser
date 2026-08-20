// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SQLite3
import Testing
import WebKit

@testable import Linen

/// The importer against real file shapes: Chrome's JSON and epoch, Safari's
/// plist and epoch, and each history schema via a fixture database - the
/// SQL is the part reading code can't check.
@MainActor
@Suite(.boundedWebViews)
struct BrowserImportTests {
    // MARK: - Bookmarks

    @Test func chromeBookmarksComeOutOfEveryFolder() throws {
        let json = """
        {"roots": {
            "bookmark_bar": {"type": "folder", "children": [
                {"type": "url", "name": "Example", "url": "https://example.com/", "date_added": "13380000000000000"},
                {"type": "folder", "name": "Work", "children": [
                    {"type": "url", "name": "Docs", "url": "https://docs.example.com/"}
                ]}
            ]},
            "other": {"type": "folder", "children": [
                {"type": "url", "name": "Deep", "url": "https://deep.example.com/"}
            ]}
        }}
        """
        let marks = BrowserImport.chromeBookmarks(from: Data(json.utf8))
        #expect(Set(marks.map(\.url)) == [
            "https://example.com/", "https://docs.example.com/", "https://deep.example.com/",
        ])
        #expect(marks.first { $0.url == "https://example.com/" }?.title == "Example")
    }

    @Test func safariBookmarksComeOutOfNestedFolders() throws {
        let plist: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                    "URLString": "https://example.com/",
                    "URIDictionary": ["title": "Example"],
                ],
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Children": [[
                        "WebBookmarkType": "WebBookmarkTypeLeaf",
                        "URLString": "https://nested.example.com/",
                        "URIDictionary": ["title": "Nested"],
                    ],
                ],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let marks = BrowserImport.safariBookmarks(from: data)
        #expect(Set(marks.map(\.url)) == ["https://example.com/", "https://nested.example.com/"])
        #expect(marks.first { $0.url == "https://nested.example.com/" }?.title == "Nested")
    }

    // MARK: - Epochs

    @Test func chromeTimeIsMicrosecondsSinceSixteenOhOne() {
        // 1970-01-01 in Chrome's clock.
        #expect(BrowserImport.chromeDate(11_644_473_600_000_000) == Date(timeIntervalSince1970: 0))
        #expect(BrowserImport.chromeDate(0) == .distantPast)
    }

    @Test func safariTimeIsSecondsSinceTwoThousandOne() {
        #expect(BrowserImport.safariDate(100) == Date(timeIntervalSinceReferenceDate: 100))
        #expect(BrowserImport.safariDate(0) == .distantPast)
    }

    // MARK: - Merge

    @Test func bookmarksBecomeOneCollapsedFolderOfColdTabs() {
        let model = BrowserModel(database: .temporary())
        let folder = model.importBookmarksFolder(named: "Safari Bookmarks", entries: [
            .init(url: "https://example.com/", title: "Example", date: .distantPast),
            .init(url: "https://docs.example.com/", title: "Docs", date: .distantPast),
            // Not a web page; a bookmarklet must not become a tab.
            .init(url: "javascript:void(0)", title: "Bookmarklet", date: .distantPast),
        ])

        #expect(folder?.name == "Safari Bookmarks")
        #expect(folder?.isExpanded == false)
        #expect(folder.map { model.tabs(in: $0).count } == 2)
        // Imported in the background: nothing steals the active tab, and
        // nothing has loaded - cold views carry no page until activated.
        #expect(model.tabs.allSatisfy { $0.webView.url == nil })
    }

    /// The half the confirmation dialog reads out loud. A scan that found
    /// nothing must say so rather than offering "0 pages and 0 bookmarks".
    @Test func theSummaryNamesOnlyWhatItActuallyFound() {
        #expect(BrowserImport.Summary(pages: 1, bookmarks: 1).phrase == "1 page of history and 1 bookmark")
        #expect(BrowserImport.Summary(pages: 12, bookmarks: 0).phrase == "12 pages of history")
        #expect(BrowserImport.Summary(pages: 0, bookmarks: 3).phrase == "3 bookmarks")
        #expect(BrowserImport.Summary().isEmpty)
    }

    /// Reading and writing are two steps now: the dialog counts a payload,
    /// and only `apply` puts anything into the browser.
    @Test func applyingAPayloadWritesBothHalves() {
        let model = BrowserModel(database: .temporary())
        let payload = BrowserImport.Payload(
            pages: [.init(url: "https://visited.example/", title: "Visited", date: .now)],
            bookmarks: [.init(url: "https://saved.example/", title: "Saved", date: .distantPast)],
            folderName: "Chrome Bookmarks"
        )

        #expect(payload.summary.pages == 1)
        #expect(payload.summary.bookmarks == 1)
        // Scanning alone changes nothing.
        #expect(model.history.entries.isEmpty)

        BrowserImport.apply(payload, into: model)
        #expect(model.history.entries.map(\.url) == ["https://visited.example/"])
        #expect(model.folders.first?.name == "Chrome Bookmarks")
    }

    @Test func mergeKeepsTheNewerVisitAndReportsOnlyNewURLs() {
        let history = HistoryStore(database: .temporary())
        history.record(url: "https://known.example/", title: "Known")

        let added = history.merge([
            // Older visit of a known page: must not replace the fresh one.
            .init(url: "https://known.example/", title: "Stale", date: .distantPast),
            .init(url: "https://new.example/", title: "New", date: Date(timeIntervalSinceNow: -60)),
            // Unrecordable schemes never land.
            .init(url: "file:///etc/hosts", title: "No", date: .now),
        ])

        #expect(added == 1)
        #expect(history.entries.first?.title == "Known")
        #expect(history.entries.map(\.url).contains("https://new.example/"))
        #expect(!history.entries.map(\.url).contains("file:///etc/hosts"))
    }
}

/// The two history queries against databases with the real schemas.
@MainActor
struct BrowserImportDatabaseTests {
    private func makeDatabase(_ statements: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-import-fixture-\(UUID().uuidString).db")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        for sql in statements {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        return url
    }

    @Test func chromeHistoryRowsReadTheUrlsTable() throws {
        let db = try makeDatabase([
            "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_time INTEGER)",
            "INSERT INTO urls VALUES (1, 'https://example.com/', 'Example', 13380000000000000)",
            "INSERT INTO urls VALUES (2, 'https://old.example/', '', 13370000000000000)",
        ])
        let rows = BrowserImport.testHistoryRows(chrome: db)
        #expect(rows.count == 2)
        #expect(rows.first?.url == "https://example.com/")
        // An untitled page shows its address, same as live recording.
        #expect(rows.last?.title == "https://old.example/")
    }

    @Test func safariHistoryRowsJoinItemsAndVisits() throws {
        let db = try makeDatabase([
            "CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT)",
            """
            CREATE TABLE history_visits (
                id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT
            )
            """,
            "INSERT INTO history_items VALUES (1, 'https://example.com/')",
            "INSERT INTO history_visits VALUES (1, 1, 700000000, 'Old Title')",
            "INSERT INTO history_visits VALUES (2, 1, 800000000, 'New Title')",
        ])
        let rows = BrowserImport.testHistoryRows(safari: db)
        #expect(rows.count == 1)
        #expect(rows.first?.url == "https://example.com/")
        #expect(rows.first?.date == Date(timeIntervalSinceReferenceDate: 800000000))
    }
}
