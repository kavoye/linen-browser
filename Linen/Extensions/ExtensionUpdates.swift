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
            let package = try await ChromeWebStore.downloadPackage(id: id)
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("linen-ext-update-\(id).zip")
            try package.write(to: scratch, options: .atomic)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let candidate = try await WKWebExtension(resourceBaseURL: scratch)
            let version = candidate.version ?? ""
            guard isNewer(version, than: record.version) else {
                updateChecks[id] = quietly ? nil : .upToDate
                return
            }
            if quietly {
                guard asksForNothingNew(candidate, replacing: id) else {
                    Pipeline.log.notice("ext: \(id, privacy: .public) \(version, privacy: .public) wants more access, leaving it")
                    return
                }
            } else if await !accepts(candidate, replacing: id, named: record.displayName) {
                updateChecks[id] = nil
                return
            }
            try await replacePackage(
                package,
                id: id,
                name: candidate.displayName,
                version: version
            )
            updateChecks[id] = .updated(version)
            Pipeline.log.notice("ext: updated \(id, privacy: .public) to \(version, privacy: .public)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            updateChecks[id] = quietly ? nil : .failed(message)
            Pipeline.log.error("ext: update of \(id, privacy: .public) failed: \(error, privacy: .public)")
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

    private func asksForNothingNew(_ candidate: WKWebExtension, replacing id: String) -> Bool {
        let granted = grantedPermissions(id: id)
        return candidate.requestedPermissions.allSatisfy { granted.contains($0.rawValue) }
    }

    private func accepts(
        _ candidate: WKWebExtension,
        replacing id: String,
        named name: String
    ) async -> Bool {
        let granted = grantedPermissions(id: id)
        let asked = candidate.requestedPermissions.filter { !granted.contains($0.rawValue) }
        guard !asked.isEmpty else { return true }
        return await ExtensionConsent.confirmRuntimeGrant(
            name: candidate.displayName ?? name,
            permissions: Set(asked),
            matchPatterns: candidate.allRequestedMatchPatterns,
            in: NSApp.keyWindow ?? NSApp.mainWindow
        )
    }
}
