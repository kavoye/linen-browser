// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Observation
import os

@MainActor
@Observable
final class HistoryStore {
    nonisolated enum Transition: String, Codable, Sendable, CaseIterable {
        case link
        case typed
        case reload
        case formSubmit
        case backForward
        case agent
        case imported
        case unknown

        var carriesReferrer: Bool {
            self == .link || self == .formSubmit
        }
    }

    nonisolated struct Visit: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
        static let databaseTableName = "historyVisit"

        var id: Int64?
        var url: String
        var visitedAt: Date
        var transition: Transition
        var fromVisit: Int64?

        static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
            .timeIntervalSinceReferenceDate
        }

        static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
            .timeIntervalSinceReferenceDate
        }
    }

    nonisolated struct VisitedPage: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
        var id: Int64
        var url: String
        var title: String
        var visitedAt: Date
        var transition: Transition

        static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
            .timeIntervalSinceReferenceDate
        }

        var entry: Entry {
            Entry(url: url, title: title, date: visitedAt)
        }
    }

    nonisolated struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
        static let databaseTableName = "historyPage"

        var id: String {
            url
        }
        var url: String
        var title: String
        var visitCount: Int
        var lastVisit: Date

        var date: Date {
            lastVisit
        }

        static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
            .timeIntervalSinceReferenceDate
        }

        static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
            .timeIntervalSinceReferenceDate
        }

        init(url: String, title: String, visitCount: Int = 1, lastVisit: Date) {
            self.url = url
            self.title = title
            self.visitCount = visitCount
            self.lastVisit = lastVisit
        }

        init(url: String, title: String, date: Date) {
            self.init(url: url, title: title, lastVisit: date)
        }
    }

    private(set) var entries: [Entry] = []
    private(set) var visits: [VisitedPage] = []
    private(set) var count = 0

    private let database: AppDatabase
    private let windowSize: Int

    init(database: AppDatabase = .shared, windowSize: Int = 3000) {
        self.database = database
        self.windowSize = windowSize
        reload()
    }

    nonisolated static func isRecordable(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        return !url.hasPrefix("https://linen.local")
    }

    @discardableResult
    func record(
        url: String,
        title: String,
        transition: Transition = .typed,
        fromVisit: Int64? = nil
    ) -> Int64? {
        guard Self.isRecordable(url) else { return nil }
        let title = title.isEmpty ? url : title
        let saved = write { db -> (entry: Entry, isNew: Bool, visitID: Int64)? in
            let known = try Entry.fetchOne(db, key: url)
            let now = Date().timeIntervalSinceReferenceDate
            try db.execute(
                sql: """
                    INSERT INTO historyPage (url, title, visitCount, lastVisit)
                    VALUES (?, ?, 1, ?)
                    ON CONFLICT(url) DO UPDATE SET
                        title = excluded.title,
                        visitCount = visitCount + 1,
                        lastVisit = excluded.lastVisit
                    """,
                arguments: [url, title, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO historyVisit (url, visitedAt, transition, fromVisit)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [url, now, transition.rawValue, transition.carriesReferrer ? fromVisit : nil]
            )
            let visitID = db.lastInsertedRowID
            guard let entry = try Entry.fetchOne(db, key: url) else { return nil }
            return (entry, known == nil, visitID)
        }
        guard let saved = saved.flatMap({ $0 }) else { return nil }

        entries.removeAll { $0.url == url }
        entries.insert(saved.entry, at: 0)
        if entries.count > windowSize {
            entries.removeLast(entries.count - windowSize)
        }
        visits.insert(
            VisitedPage(
                id: saved.visitID,
                url: url,
                title: title,
                visitedAt: saved.entry.lastVisit,
                transition: transition
            ),
            at: 0
        )
        if visits.count > windowSize {
            visits.removeLast(visits.count - windowSize)
        }
        if saved.isNew {
            count += 1
        }
        return saved.visitID
    }

    func removeVisit(_ id: Int64) {
        let url = write { db -> String? in
            let url = try String.fetchOne(
                db, sql: "SELECT url FROM historyVisit WHERE id = ?", arguments: [id]
            )
            guard let url else { return nil }
            try db.execute(sql: "DELETE FROM historyVisit WHERE id = ?", arguments: [id])
            try db.execute(
                sql: """
                    UPDATE historyPage SET
                        visitCount = (
                            SELECT COUNT(*) FROM historyVisit
                            WHERE historyVisit.url = historyPage.url
                        ),
                        lastVisit = COALESCE(
                            (
                                SELECT MAX(visitedAt) FROM historyVisit
                                WHERE historyVisit.url = historyPage.url
                            ),
                            lastVisit
                        )
                    WHERE url = ?
                    """,
                arguments: [url]
            )
            try db.execute(sql: "DELETE FROM historyPage WHERE visitCount = 0")
            return url
        }
        guard url != nil else { return }
        reload()
    }

    func referrerChain(to visitID: Int64, limit: Int = 12) -> [VisitedPage] {
        let chain = read { db -> [VisitedPage] in
            var found: [VisitedPage] = []
            var next: Int64? = visitID
            var seen: Set<Int64> = []
            while let id = next, found.count < limit, seen.insert(id).inserted {
                let row = try VisitedPage.fetchOne(
                    db,
                    sql: """
                        SELECT historyVisit.id, historyVisit.url, historyPage.title,
                               historyVisit.visitedAt, historyVisit.transition
                        FROM historyVisit
                        JOIN historyPage ON historyPage.url = historyVisit.url
                        WHERE historyVisit.id = ?
                        """,
                    arguments: [id]
                )
                guard let row else { break }
                found.append(row)
                next = try Int64.fetchOne(
                    db,
                    sql: "SELECT fromVisit FROM historyVisit WHERE id = ?",
                    arguments: [id]
                )
            }
            return found
        } ?? []
        return chain.reversed()
    }

    @discardableResult
    func merge(_ imported: [Entry]) -> Int {
        let arriving = imported.filter { Self.isRecordable($0.url) }
        guard !arriving.isEmpty else { return 0 }

        let added = write { db -> Int in
            var added = 0
            for entry in arriving {
                if try Entry.fetchOne(db, key: entry.url) == nil {
                    added += 1
                }
                try db.execute(
                    sql: """
                        INSERT INTO historyPage (url, title, visitCount, lastVisit)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(url) DO UPDATE SET
                            title = CASE WHEN excluded.lastVisit > lastVisit
                                THEN excluded.title ELSE title END,
                            visitCount = visitCount + excluded.visitCount,
                            lastVisit = max(lastVisit, excluded.lastVisit)
                        """,
                    arguments: [
                        entry.url, entry.title, entry.visitCount,
                        entry.lastVisit.timeIntervalSinceReferenceDate,
                    ]
                )
                try db.execute(
                    sql: """
                        INSERT INTO historyVisit (url, visitedAt, transition, fromVisit)
                        VALUES (?, ?, ?, NULL)
                        """,
                    arguments: [
                        entry.url,
                        entry.lastVisit.timeIntervalSinceReferenceDate,
                        Transition.imported.rawValue,
                    ]
                )
            }
            return added
        }
        reload()
        return added ?? 0
    }

    func search(_ query: String, limit: Int = 6) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Array(entries.prefix(limit)) }
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: needle) else { return [] }

        return read { db in
            try Entry.fetchAll(
                db,
                sql: """
                    SELECT historyPage.* FROM historyPage
                    JOIN historyPage_ft ON historyPage_ft.rowid = historyPage.rowid
                        AND historyPage_ft MATCH ?
                    ORDER BY historyPage.visitCount DESC, historyPage.lastVisit DESC
                    LIMIT ?
                    """,
                arguments: [pattern, limit]
            )
        } ?? []
    }

    func search(matching query: HistoryQuery, limit: Int = 6) -> [Entry] {
        guard let range = query.dateRange else { return search(query.terms, limit: limit) }
        let lower = range.lowerBound.timeIntervalSinceReferenceDate
        let upper = range.upperBound.timeIntervalSinceReferenceDate
        let needle = query.terms.trimmingCharacters(in: .whitespacesAndNewlines)

        if needle.isEmpty {
            return read { db in
                try Entry.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT historyPage.* FROM historyPage
                        JOIN historyVisit ON historyVisit.url = historyPage.url
                            AND historyVisit.visitedAt >= ? AND historyVisit.visitedAt < ?
                        ORDER BY historyPage.lastVisit DESC
                        LIMIT ?
                        """,
                    arguments: [lower, upper, limit]
                )
            } ?? []
        }

        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: needle) else { return [] }
        return read { db in
            try Entry.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT historyPage.* FROM historyPage
                    JOIN historyPage_ft ON historyPage_ft.rowid = historyPage.rowid
                        AND historyPage_ft MATCH ?
                    JOIN historyVisit ON historyVisit.url = historyPage.url
                        AND historyVisit.visitedAt >= ? AND historyVisit.visitedAt < ?
                    ORDER BY historyPage.visitCount DESC, historyPage.lastVisit DESC
                    LIMIT ?
                    """,
                arguments: [pattern, lower, upper, limit]
            )
        } ?? []
    }

    func remove(_ entry: Entry) {
        let deleted = write { db in
            try Entry.deleteOne(db, key: entry.url)
        }
        guard deleted == true else { return }
        entries.removeAll { $0.url == entry.url }
        visits.removeAll { $0.url == entry.url }
        count -= 1
    }

    func clear() {
        write { db in
            _ = try Entry.deleteAll(db)
        }
        reload()
    }

    func removeEntries(since date: Date) {
        deleteVisits(matching: "visitedAt >= ?", date)
    }

    func prune(retention: HistoryRetention) {
        guard let maximumAge = retention.maximumAge else { return }
        deleteVisits(matching: "visitedAt < ?", Date(timeIntervalSinceNow: -maximumAge))
    }

    private func deleteVisits(matching condition: String, _ date: Date) {
        write { db in
            let cutoff = date.timeIntervalSinceReferenceDate
            let touched = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT url FROM historyVisit WHERE \(condition)",
                arguments: [cutoff]
            )
            guard !touched.isEmpty else { return }
            try db.execute(
                sql: "DELETE FROM historyVisit WHERE \(condition)",
                arguments: [cutoff]
            )
            try db.execute(
                sql: """
                    UPDATE historyPage SET
                        visitCount = (
                            SELECT COUNT(*) FROM historyVisit
                            WHERE historyVisit.url = historyPage.url
                        ),
                        lastVisit = COALESCE(
                            (
                                SELECT MAX(visitedAt) FROM historyVisit
                                WHERE historyVisit.url = historyPage.url
                            ),
                            lastVisit
                        )
                    WHERE url IN (\(databaseQuestionMarks(count: touched.count)))
                    """,
                arguments: StatementArguments(touched)
            )
            try db.execute(sql: "DELETE FROM historyPage WHERE visitCount = 0")
        }
        reload()
    }

    // MARK: - Storage

    private func reload() {
        let loaded = read { db -> ([Entry], [VisitedPage], Int) in
            let entries = try Entry
                .order(sql: "lastVisit DESC")
                .limit(windowSize)
                .fetchAll(db)
            let visits = try VisitedPage.fetchAll(
                db,
                sql: """
                    SELECT historyVisit.id, historyVisit.url, historyPage.title,
                           historyVisit.visitedAt, historyVisit.transition
                    FROM historyVisit
                    JOIN historyPage ON historyPage.url = historyVisit.url
                    ORDER BY historyVisit.visitedAt DESC
                    LIMIT ?
                    """,
                arguments: [windowSize]
            )
            return (entries, visits, try Entry.fetchCount(db))
        }
        guard let loaded else { return }
        entries = loaded.0
        visits = loaded.1
        count = loaded.2
    }

    @discardableResult
    private func write<T>(_ updates: (Database) throws -> T) -> T? {
        do {
            return try database.writer.write(updates)
        } catch {
            Pipeline.log.error("history: write failed: \(error, privacy: .public)")
            return nil
        }
    }

    private func read<T>(_ value: (Database) throws -> T) -> T? {
        do {
            return try database.writer.read(value)
        } catch {
            Pipeline.log.error("history: read failed: \(error, privacy: .public)")
            return nil
        }
    }
}
