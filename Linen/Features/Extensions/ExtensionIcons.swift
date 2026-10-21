// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import WebKit

@MainActor
final class ExtensionIcons {
    private var cache: [String: NSImage] = [:]

    func cached(for id: String) -> NSImage? {
        cache[id]
    }

    func store(_ icon: NSImage, for id: String) {
        cache[id] = icon
    }

    func forget(_ id: String) {
        cache[id] = nil
    }

    func icon(
        for id: String, context: WKWebExtensionContext?, record: InstalledExtension?, packageURL: URL
    ) async -> NSImage? {
        if let cached = cache[id] {
            return cached
        }

        if let icon = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
            cache[id] = icon
            return icon
        }

        guard let record else { return nil }

        do {
            let webExtension: WKWebExtension
            if let path = record.bundlePath, let bundle = Bundle(path: path) {
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                webExtension = try await WKWebExtension(resourceBaseURL: packageURL)
            }
            let icon = webExtension.icon(for: CGSize(width: 32, height: 32))
            if let icon {
                cache[id] = icon
            }
            return icon
        } catch {
            Pipeline.log.error("Extension icon loading failed")
            return nil
        }
    }
}
