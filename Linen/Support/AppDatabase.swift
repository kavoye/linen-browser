// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import os

struct AppDatabase: Sendable {
    let writer: any DatabaseWriter
    let isEphemeral: Bool

    static let shared: AppDatabase = {
        guard !isRunningTests else { return .temporary() }
        guard ownsSession else { return .temporary() }
        return AppDatabase(at: defaultURL)
    }()

    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static let ownsSession: Bool = {
        guard !isRunningTests else { return false }
        guard SessionLock.take(at: supportDirectory.appendingPathComponent("Linen.lock")) != nil else {
            Pipeline.log.error("db: another copy of Linen has this session open; this one keeps nothing")
            return false
        }
        return true
    }()

    static var supportDirectory: URL {
        #if DEBUG
        if let staged = StageMode.home {
            return staged
        }
        #endif
        if isRunningTests {
            return testSupportDirectory
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
    }

    /// A test run keeps its files to itself: profiles, permissions, zoom and
    /// the download list all hang off this, and none of them belong in the
    /// support directory a person's copy of Linen is using.
    private nonisolated static let testSupportDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Linen-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var defaultURL: URL {
        supportDirectory.appendingPathComponent("Linen.sqlite")
    }

    static func url(forProfile id: UUID) -> URL {
        supportDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("Linen.sqlite")
    }

    init(at url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let pool = try DatabasePool(path: url.path, configuration: Self.configuration)
            try Self.migrator.migrate(pool)
            try pool.write { try Self.defineSchema(in: $0) }
            writer = pool
            isEphemeral = false
        } catch {
            Pipeline.log.error("db: opening \(url.path, privacy: .public) failed: \(error, privacy: .public)")
            writer = Self.memoryWriter()
            isEphemeral = true
        }
    }

    private init(writer: any DatabaseWriter) {
        self.writer = writer
        isEphemeral = true
    }

    static func temporary() -> AppDatabase {
        AppDatabase(writer: memoryWriter())
    }

    private static func memoryWriter() -> any DatabaseWriter {
        // swiftlint:disable:next force_try
        let queue = try! DatabaseQueue(configuration: configuration)
        try? migrator.migrate(queue)
        try? queue.write { try defineSchema(in: $0) }
        return queue
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in try defineSchema(in: db) }
        return migrator
    }

    private nonisolated static func defineSchema(in db: Database) throws {
        try db.create(table: "historyPage", options: .ifNotExists) {  t in
            t.primaryKey("url", .text)
            t.column("title", .text).notNull()
            t.column("visitCount", .integer).notNull().defaults(to: 1)
            t.column("lastVisit", .double).notNull().indexed()
        }

        try db.create(virtualTable: "historyPage_ft", options: .ifNotExists, using: FTS5()) { t in
            t.synchronize(withTable: "historyPage")
            t.tokenizer = .unicode61()
            t.prefixes = [2, 3]
            t.column("url")
            t.column("title")
        }

        try db.create(table: "sessionFolder", options: .ifNotExists) {  t in
            t.primaryKey("id", .blob)
            t.column("position", .integer).notNull()
            t.column("name", .text).notNull()
            t.column("color", .text).notNull()
            t.column("isExpanded", .boolean).notNull()
        }

        try db.create(table: "sessionTab", options: .ifNotExists) {  t in
            t.primaryKey("id", .blob)
            t.column("title", .text).notNull()
            t.column("url", .text).notNull()
            t.column("state", .blob)
            t.column("pinnedURL", .text)
            t.column("pinnedTitle", .text)
            t.column("internalPage", .text)
            t.column("isActive", .boolean).notNull().defaults(to: false)
        }

        try db.create(table: "sessionItem", options: .ifNotExists) {  t in
            t.primaryKey("position", .integer)
            t.column("tabID", .blob).references("sessionTab", onDelete: .cascade)
            t.column("folderID", .blob).references("sessionFolder", onDelete: .cascade)
            t.column("parentID", .blob).references("sessionFolder", onDelete: .cascade)
        }

        try db.create(table: "agentTrace", options: .ifNotExists) {  t in
            t.primaryKey("id", .blob)
            t.column("tabID", .blob).notNull().indexed()
            t.column("prompt", .text).notNull()
            t.column("startedAt", .datetime).notNull()
            t.column("response", .text).notNull()
            t.column("state", .text).notNull()
            t.column("finishedAt", .datetime)
            t.column("providerID", .text)
        }

        if try !db.columns(in: "agentTrace").contains(where: { $0.name == "providerID" }) {
            try db.alter(table: "agentTrace") { t in
                t.add(column: "providerID", .text)
            }
        }

        try db.create(table: "agentStep", options: .ifNotExists) {  t in
            t.primaryKey("id", .blob)
            t.column("traceID", .blob)
                .notNull()
                .indexed()
                .references("agentTrace", onDelete: .cascade)
            t.column("position", .integer).notNull()
            t.column("kind", .text).notNull()
            t.column("title", .text).notNull()
            t.column("toolName", .text)
            t.column("startedAt", .datetime).notNull()
            t.column("detail", .text)
            t.column("links", .text).notNull()
            t.column("state", .text).notNull()
        }

        try db.create(table: "agentUsage", options: .ifNotExists) {  t in
            t.primaryKey("tabID", .blob)
            t.column("requestCount", .integer).notNull()
            t.column("inputTokens", .integer).notNull()
            t.column("cachedTokens", .integer).notNull()
            t.column("outputTokens", .integer).notNull()
            t.column("estimatedContextTokens", .integer).notNull()
        }

        try db.create(table: "historyVisit", options: .ifNotExists) {  t in
            t.autoIncrementedPrimaryKey("id")
            t.column("url", .text)
                .notNull()
                .indexed()
                .references("historyPage", onDelete: .cascade)
            t.column("visitedAt", .double).notNull().indexed()
            t.column("transition", .text).notNull()
            t.column("fromVisit", .integer).references("historyVisit", onDelete: .setNull)
        }

        try db.create(table: "sessionSplitTree", options: .ifNotExists) { t in
            t.primaryKey("id", .blob)
            t.column("position", .integer).notNull()
            t.column("tree", .text).notNull()
        }

        try db.create(table: "sessionSplitPane", options: .ifNotExists) {  t in
            t.primaryKey("tabID", .blob)
                .references("sessionTab", onDelete: .cascade)
            t.column("splitID", .blob).notNull().indexed()
            t.column("rowIndex", .integer).notNull()
            t.column("columnIndex", .integer).notNull()
            t.column("rowFraction", .double).notNull()
            t.column("columnFraction", .double).notNull()
        }
    }
}

struct SessionLock: Sendable {
    let descriptor: CInt

    @discardableResult
    static func take(at url: URL) -> SessionLock? {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return SessionLock(descriptor: descriptor)
    }

    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
