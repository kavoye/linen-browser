// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB

nonisolated struct ProfileFacts: Equatable, Sendable {
    var tabs = 0
    var folders = 0
    var pages = 0
    var firstVisit: Date?
    var extensions = 0
    var permissionSites = 0
    var bytes: Int64 = 0

    static let empty = ProfileFacts()
}

extension ProfileFacts {
    nonisolated struct Sources: Sendable {
        var database: URL?
        var profileID: UUID
        var extensionLibrary: URL
        var permissions: URL
        var support: URL
        var holdsOtherProfiles: Bool
    }

    @MainActor
    static func sources(for profile: Profile) -> Sources? {
        guard !profile.isPrivate else { return nil }
        return Sources(
            database: profile.databaseURL,
            profileID: profile.id,
            extensionLibrary: ExtensionLibrary.defaultBaseDirectory,
            permissions: profile.permissionsFile,
            support: profile.supportDirectory,
            holdsOtherProfiles: profile.isOriginal
        )
    }

    @MainActor
    static func load(for profile: Profile) async -> ProfileFacts {
        guard let sources = sources(for: profile) else { return .empty }
        return await Task.detached(priority: .utility) { read(sources) }.value
    }

    nonisolated static func read(_ sources: Sources) -> ProfileFacts {
        var facts = ProfileFacts()
        if let database = sources.database, let counts = counts(in: database) {
            facts.tabs = counts.tabs
            facts.folders = counts.folders
            facts.pages = counts.pages
            facts.firstVisit = counts.firstVisit
        }
        facts.extensions = ExtensionLibrary.enabledCount(
            forProfile: sources.profileID,
            in: sources.extensionLibrary
        )
        facts.permissionSites = SitePermissions.changedSiteCount(in: sources.permissions)
        facts.bytes = size(of: sources.support, skippingProfiles: sources.holdsOtherProfiles)
        return facts
    }

    nonisolated private struct Counts {
        var tabs: Int
        var folders: Int
        var pages: Int
        var firstVisit: Date?
    }

    nonisolated private static func counts(in database: URL) -> Counts? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        var configuration = Configuration()
        configuration.readonly = true
        guard let queue = try? DatabaseQueue(path: database.path, configuration: configuration)
        else { return nil }

        return try? queue.read { db in
            let earliest = try? Double.fetchOne(db, sql: "SELECT MIN(visitedAt) FROM historyVisit")
            return Counts(
                tabs: count(db, table: "sessionTab"),
                folders: count(db, table: "sessionFolder"),
                pages: count(db, table: "historyPage"),
                firstVisit: earliest.map { Date(timeIntervalSinceReferenceDate: $0) }
            )
        }
    }

    nonisolated private static func count(_ db: Database, table: String) -> Int {
        (try? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)")) ?? 0
    }

    nonisolated private static func size(of root: URL, skippingProfiles: Bool) -> Int64 {
        let files = FileManager.default
        guard files.fileExists(atPath: root.path) else { return 0 }
        guard let walk = files.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in walk {
            if skippingProfiles, url.lastPathComponent == "Profiles" {
                walk.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true, let bytes = values?.totalFileAllocatedSize
            else { continue }
            total += Int64(bytes)
        }
        return total
    }
}

enum ProfileMaintenance {
    @MainActor
    static func clearHistory(of profile: Profile) {
        guard let database = profile.databaseURL,
              FileManager.default.fileExists(atPath: database.path)
        else { return }
        HistoryStore(database: AppDatabase(at: database)).clear()
    }
}
