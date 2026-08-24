// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated struct SafariExtension: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var version: String
    var bundlePath: String
    var containingAppName: String
}

nonisolated enum SafariExtensionCatalog {
    static let extensionPoint = "com.apple.Safari.web-extension"

    static var searchRoots: [URL] {
        var roots = [URL(filePath: "/Applications", directoryHint: .isDirectory)]
        if let home = try? FileManager.default.url(
            for: .applicationDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            roots.append(home)
        }
        return roots
    }

    static func installed(in roots: [URL] = searchRoots) -> [SafariExtension] {
        var found: [String: SafariExtension] = [:]
        for root in roots {
            for app in applications(under: root) {
                for extensionBundle in webExtensions(in: app) {
                    found[extensionBundle.id] = extensionBundle
                }
            }
        }
        return found.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func applications(under root: URL) -> [URL] {
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var apps: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                apps.append(entry)
                continue
            }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let nested = try? files.contentsOfDirectory(
                      at: entry,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { continue }
            apps.append(contentsOf: nested.filter { $0.pathExtension == "app" })
        }
        return apps
    }

    private static func webExtensions(in app: URL) -> [SafariExtension] {
        let plugIns = app.appending(path: "Contents/PlugIns", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: plugIns,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let appName = app.deletingPathExtension().lastPathComponent
        return entries
            .filter { $0.pathExtension == "appex" }
            .compactMap { describe($0, containingApp: appName) }
    }

    static func describe(_ bundleURL: URL, containingApp: String) -> SafariExtension? {
        guard let bundle = Bundle(url: bundleURL),
              let identifier = bundle.bundleIdentifier,
              let details = bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any],
              details["NSExtensionPointIdentifier"] as? String == extensionPoint
        else { return nil }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        return SafariExtension(
            id: identifier,
            displayName: containingApp,
            version: version,
            bundlePath: bundleURL.path,
            containingAppName: containingApp
        )
    }
}
