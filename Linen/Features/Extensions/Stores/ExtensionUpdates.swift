// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import OSLog
import WebKit

enum UpdateCheck: Equatable {
    case checking
    case upToDate
    case updated(String)
    case failed(String)
}

extension ExtensionManager {
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    private static let lastSweepKey = "extensions.lastUpdateCheck"

    private static let sweepInterval: TimeInterval = 24 * 60 * 60

    private static let heldUpdatesKey = "extensions.heldUpdates"

    static let downloadPackageFromStore: (InstalledExtension) async throws -> Data = { record in
        switch record.source {
        case .chrome:
            try await ChromeWebStore.downloadPackage(id: record.id)
        case .firefox:
            try await FirefoxAddons.downloadPackage(slug: record.id)
        }
    }

    static var downloadPackage = downloadPackageFromStore

    static func savedHeldUpdates() -> [String: String] {
        defaults.dictionary(forKey: heldUpdatesKey) as? [String: String] ?? [:]
    }

    func setHeldUpdate(_ version: String?, id: String) {
        guard heldUpdates[id] != version else { return }
        heldUpdates[id] = version
        Self.defaults.set(heldUpdates, forKey: Self.heldUpdatesKey)
    }

    func updateInstalledIfDue(now: Date = Date()) async {
        let defaults = Self.defaults
        let last = defaults.object(forKey: Self.lastSweepKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.sweepInterval else { return }
        defaults.set(now, forKey: Self.lastSweepKey)

        for record in installed where !record.isSystem {
            await checkForUpdate(id: record.id, quietly: true)
        }
    }

    func checkForUpdate(id: String, quietly: Bool = false) async {
        guard let record = installedRecord(id: id), !record.isSystem else { return }
        if !quietly {
            updateChecks[id] = .checking
        }
        do {
            let package = try await Self.downloadPackage(record)
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("linen-ext-update-\(id).zip")
            try package.write(to: scratch, options: .atomic)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let candidate = try await WKWebExtension(resourceBaseURL: scratch)
            let version = candidate.version ?? ""
            guard isNewer(version, than: record.version) else {
                setHeldUpdate(nil, id: id)
                updateChecks[id] = quietly ? nil : .upToDate
                return
            }
            let added = Self.access(in: candidate, beyond: await approvedExtension(id: id))
            if quietly {
                guard added.isEmpty else {
                    setHeldUpdate(version, id: id)
                    Pipeline.log.notice("Extension update needs more access")
                    return
                }
            } else if !added.isEmpty, await !ExtensionConsent.confirmRuntimeGrant(
                name: candidate.displayName ?? record.displayName,
                permissions: added.permissions,
                matchPatterns: added.websites,
                in: NSApp.keyWindow ?? NSApp.mainWindow
            ) {
                setHeldUpdate(nil, id: id)
                updateChecks[id] = nil
                return
            }
            try await replacePackage(
                package,
                id: id,
                name: candidate.displayName,
                version: version
            )
            setHeldUpdate(nil, id: id)
            updateChecks[id] = .updated(version)
            Pipeline.log.notice("Extension updated")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            updateChecks[id] = quietly ? nil : .failed(message)
            Pipeline.log.error("Extension update failed")
        }
    }

    func clearUpdateCheck(id: String) {
        updateChecks[id] = nil
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        guard !installed.isEmpty else { return true }
        return candidate.compare(installed, options: .numeric) == .orderedDescending
    }

    struct AddedAccess {
        var permissions: Set<WKWebExtension.Permission>
        var websites: Set<WKWebExtension.MatchPattern>

        var isEmpty: Bool {
            permissions.isEmpty && websites.isEmpty
        }
    }

    static func access(in candidate: WKWebExtension, beyond approved: WKWebExtension?) -> AddedAccess {
        let approvedWebsites = approved?.allRequestedMatchPatterns ?? []
        return AddedAccess(
            permissions: candidate.requestedPermissions.subtracting(approved?.requestedPermissions ?? []),
            websites: candidate.allRequestedMatchPatterns.filter { pattern in
                !approvedWebsites.contains { $0.matches(pattern) }
            }
        )
    }

    private func approvedExtension(id: String) async -> WKWebExtension? {
        if let loaded = contexts[id]?.webExtension {
            return loaded
        }
        return try? await WKWebExtension(resourceBaseURL: packageURL(for: id))
    }
}
