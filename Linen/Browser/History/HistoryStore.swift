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
        case inPage
        case imported
        case unknown

        var carriesReferrer: Bool {
            self == .link || self == .formSubmit || self == .inPage
        }
    }

    nonisolated struct VisitedPage: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
        var id: Int64
        var url: String
        var title: String
        var visitedAt: Date
        var transition: Transition
        var trail: Int64?

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
    private(set) var hasOlderVisits = false
    private var visitLimit: Int

    func loadOlderVisits(limit: Int = 1_000) {
        guard hasOlderVisits, let oldest = visits.last else { return }
        let older = read { db in
            try Self.fetchVisits(
                db,
                before: oldest,
                limit: limit + 1
            )
        }
        guard let older else { return }
        hasOlderVisits = older.count > limit
        visits.append(contentsOf: older.prefix(limit))
        visitLimit = max(visitLimit, visits.count)
    }

    private nonisolated static func fetchVisits(
        _ db: Database,
        before oldest: VisitedPage? = nil,
        limit: Int
    ) throws -> [VisitedPage] {
        let older = oldest == nil ? "" : """
            WHERE historyVisit.visitedAt < ?
                OR (historyVisit.visitedAt = ? AND historyVisit.id < ?)
            """
        var arguments: StatementArguments = []
        if let oldest {
            let date = oldest.visitedAt.timeIntervalSinceReferenceDate
            arguments += [date, date, oldest.id]
        }
        arguments += [limit]
        return try VisitedPage.fetchAll(
            db,
            sql: """
                SELECT historyVisit.id, historyVisit.url, historyPage.title,
                       historyVisit.visitedAt, historyVisit.transition, historyVisit.trail
                FROM historyVisit
                JOIN historyPage ON historyPage.url = historyVisit.url
                \(older)
                ORDER BY historyVisit.visitedAt DESC, historyVisit.id DESC
                LIMIT ?
                """,
            arguments: arguments
        )
    }

    private let database: AppDatabase
    private let windowSize: Int

    init(database: AppDatabase = .shared, windowSize: Int = 3000) {
        self.database = database
        self.windowSize = windowSize
        visitLimit = windowSize
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
        fromVisit: Int64? = nil,
        trail: Int64? = nil
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
                    INSERT INTO historyVisit (url, visitedAt, transition, fromVisit, trail)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [url, now, transition.rawValue, transition.carriesReferrer ? fromVisit : nil, trail]
            )
            let visitID = db.lastInsertedRowID
            if trail == nil {
                try db.execute(sql: "UPDATE historyVisit SET trail = id WHERE id = ?", arguments: [visitID])
            }
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
                transition: transition,
                trail: trail ?? saved.visitID
            ),
            at: 0
        )
        if visits.count > visitLimit {
            if visitLimit > windowSize {
                visitLimit = visits.count
            } else {
                visits.removeLast(visits.count - visitLimit)
                hasOlderVisits = true
            }
        }
        if saved.isNew {
            count += 1
        }
        return saved.visitID
    }

    func retitle(visit: Int64, url: String, title: String) {
        guard !title.isEmpty else { return }
        let changed = write { db -> Bool in
            try db.execute(
                sql: """
                    UPDATE historyPage SET title = ?
                    WHERE url = ? AND title != ?
                        AND EXISTS (SELECT 1 FROM historyVisit WHERE id = ? AND url = ?)
                    """,
                arguments: [title, url, title, visit, url]
            )
            return db.changesCount > 0
        }
        guard changed == true else { return }
        for index in entries.indices where entries[index].url == url {
            entries[index].title = title
        }
        for index in visits.indices where visits[index].url == url {
            visits[index].title = title
        }
    }

    func removeVisits(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let marks = databaseQuestionMarks(count: ids.count)
        let removed = write { db -> Bool in
            let urls = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT url FROM historyVisit WHERE id IN (\(marks))",
                arguments: StatementArguments(ids)
            )
            guard !urls.isEmpty else { return false }
            try db.execute(
                sql: "DELETE FROM historyVisit WHERE id IN (\(marks))",
                arguments: StatementArguments(ids)
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
                    WHERE url IN (\(databaseQuestionMarks(count: urls.count)))
                    """,
                arguments: StatementArguments(urls)
            )
            try db.execute(sql: "DELETE FROM historyPage WHERE visitCount = 0")
            return true
        }
        guard removed == true else { return }
        reload()
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
        _ = count

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
        let visitLimit = visitLimit
        let loaded = read { db -> ([Entry], [VisitedPage], Int) in
            let entries = try Entry
                .order(sql: "lastVisit DESC")
                .limit(windowSize)
                .fetchAll(db)
            let visits = try Self.fetchVisits(db, limit: visitLimit + 1)
            return (entries, visits, try Entry.fetchCount(db))
        }
        guard let loaded else { return }
        entries = loaded.0
        hasOlderVisits = loaded.1.count > visitLimit
        visits = Array(loaded.1.prefix(visitLimit))
        count = loaded.2
    }

    @discardableResult
    private func write<T>(_ updates: (Database) throws -> T) -> T? {
        do {
            return try database.writer.write(updates)
        } catch {
            Pipeline.log.error("history: write failed")
            return nil
        }
    }

    private func read<T>(_ value: (Database) throws -> T) -> T? {
        do {
            return try database.writer.read(value)
        } catch {
            Pipeline.log.error("history: read failed")
            return nil
        }
    }
}
