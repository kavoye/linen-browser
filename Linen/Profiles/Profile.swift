// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var color: TabFolderColor

    static let originalID = UUID(uuidString: "0E000000-0000-4000-A000-000000000001")!
    static let privateID = UUID(uuidString: "0E000000-0000-4000-A000-000000000002")!

    var isOriginal: Bool {
        id == Self.originalID
    }

    var isPrivate: Bool {
        id == Self.privateID
    }

    static func original() -> Profile {
        Profile(
            id: originalID,
            name: String(localized: "Personal"),
            symbol: "person",
            color: .blue
        )
    }

    static func privateBrowsing() -> Profile {
        Profile(
            id: privateID,
            name: String(localized: "Private Browsing"),
            symbol: "eyeglasses",
            color: .gray
        )
    }
}

// MARK: - Where a profile's things live

extension Profile {
    var supportDirectory: URL {
        if isPrivate {
            return URL(filePath: NSTemporaryDirectory())
                .appending(path: "Linen-private", directoryHint: .isDirectory)
        }
        guard !isOriginal else { return AppDatabase.supportDirectory }
        return AppDatabase.supportDirectory
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var databaseURL: URL? {
        if isPrivate {
            return nil
        }
        return isOriginal ? AppDatabase.defaultURL : AppDatabase.url(forProfile: id)
    }

    @MainActor
    func makeDatabase() -> AppDatabase {
        if isPrivate {
            return .temporary()
        }
        guard let databaseURL, !isOriginal else { return .shared }
        guard AppDatabase.ownsSession else { return .temporary() }
        return AppDatabase(at: databaseURL)
    }

    var zoomFile: URL {
        supportDirectory.appendingPathComponent("page-zoom.json")
    }

    var permissionsFile: URL {
        supportDirectory.appendingPathComponent("SitePermissions.json")
    }

    var extensionsDirectory: URL {
        supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
    }

    @MainActor
    func makeDataStore() -> WKWebsiteDataStore {
        if isPrivate {
            return .nonPersistent()
        }
        #if DEBUG
        if StageMode.isActive, isOriginal {
            return StageMode.websiteDataStore()
        }
        #endif
        return isOriginal ? .default() : WKWebsiteDataStore(forIdentifier: id)
    }

    @MainActor
    static func erase(_ profile: Profile) async {
        guard !profile.isOriginal else { return }
        if !profile.isPrivate {
            try? await WKWebsiteDataStore.remove(forIdentifier: profile.id)
        }
        try? FileManager.default.removeItem(at: profile.supportDirectory)
        try? FileManager.default.removeItem(at: FaviconLoader.cacheDirectory(for: profile))
        ProfileSettingsStore.forget(profile.id)
    }
}
