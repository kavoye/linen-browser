// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Observation
import os

@MainActor
@Observable
final class TabArchive {
    nonisolated struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
        static let databaseTableName = "archivedTab"

        var id: UUID
        var title: String
        var url: String
        var archivedAt: Date
    }

    static let capacity = 500

    private(set) var entries: [Entry] = []

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
        reload()
    }

    func add(_ pages: [(title: String, url: String)], at date: Date = Date()) {
        let recordable = pages.filter { HistoryStore.isRecordable($0.url) }
        guard !recordable.isEmpty else { return }
        write { db in
            for page in recordable {
                try Entry.filter(Column("url") == page.url).deleteAll(db)
                try Entry(id: UUID(), title: page.title, url: page.url, archivedAt: date).insert(db)
            }
            try db.execute(
                sql: """
                    DELETE FROM archivedTab WHERE id NOT IN (
                        SELECT id FROM archivedTab ORDER BY archivedAt DESC LIMIT ?
                    )
                    """,
                arguments: [Self.capacity]
            )
        }
        reload()
    }

    func remove(_ entry: Entry) {
        write { db in
            _ = try Entry.deleteOne(db, key: entry.id)
        }
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        write { db in
            _ = try Entry.deleteAll(db)
        }
        reload()
    }

    func removeEntries(since date: Date) {
        write { db in
            _ = try Entry.filter(Column("archivedAt") >= date).deleteAll(db)
        }
        reload()
    }

    func prune(retention: HistoryRetention, now: Date = Date()) {
        guard let maximumAge = retention.maximumAge else { return }
        write { db in
            _ = try Entry.filter(Column("archivedAt") < now.addingTimeInterval(-maximumAge)).deleteAll(db)
        }
        reload()
    }

    private func reload() {
        entries = (try? database.writer.read { db in
            try Entry.order(Column("archivedAt").desc).fetchAll(db)
        }) ?? []
    }

    private func write(_ body: (Database) throws -> Void) {
        do {
            try database.writer.write(body)
        } catch {
            Pipeline.log.error("tab archive: write failed")
        }
    }
}
