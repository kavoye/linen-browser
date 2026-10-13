// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

nonisolated struct ExternalAppMatch: Sendable {
    let url: URL
    let name: String
    var bundleIdentifier: String?
}

@MainActor
enum ExternalApp {
    typealias Match = ExternalAppMatch

    private nonisolated static let webSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "file", "javascript", "webkit-extension",
    ]

    nonisolated static func staysInWebView(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return webSchemes.contains(scheme)
    }

    static var openerForTesting: ((URL) -> Void)?
    static var requestObserverForTesting: ((URL, String) -> Void)?
    static var resolverForTesting: ((URL) async -> Match?)?
    static var presenterForTesting: ((NSAlert) async -> NSApplication.ModalResponse)?

    private static var isAsking = false

    static func offerToOpen(
        _ url: URL,
        from origin: String,
        policy: TabExternalAppPolicy,
        in window: NSWindow?
    ) async {
        if let requestObserverForTesting {
            requestObserverForTesting(url, origin)
            return
        }
        guard window != nil || presenterForTesting != nil, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        let match = if let resolverForTesting {
            await resolverForTesting(url)
        } else {
            await application(toOpen: url)
        }

        guard let match else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No app can open this link.")
            alert.informativeText = String(localized: "No app installed on this Mac handles \(url.scheme ?? "") links.")
            alert.addButton(withTitle: String(localized: "OK"))
            _ = await present(alert, in: window)
            return
        }

        let permission = match.bundleIdentifier.flatMap { bundleIdentifier in
            url.scheme.map { scheme in
                ExternalAppPermission(scheme: scheme.lowercased(), bundleIdentifier: bundleIdentifier, name: match.name)
            }
        }
        if let permission, policy.allows(permission, from: origin) {
            open(url)
            return
        }

        let alert = confirmation(
            for: match,
            from: origin,
            canRemember: permission != nil && !origin.isEmpty,
            isPrivate: policy.isPrivate
        )
        guard await present(alert, in: window) == .alertFirstButtonReturn else { return }
        if let permission, alert.suppressionButton?.state == .on {
            policy.remember(permission, from: origin)
        }
        open(url)
    }

    static func confirmation(for app: Match, from origin: String, canRemember: Bool, isPrivate: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.icon = NSWorkspace.shared.icon(forFile: app.url.path)
        alert.messageText = String(localized: "Open \(app.name)?")
        if origin.isEmpty {
            alert.informativeText = String(localized: "This page wants to open \(app.name).")
        } else {
            let site = SitePermissions.displayName(for: origin)
            alert.informativeText = String(localized: "\(site) wants to open \(app.name).")
        }
        alert.addButton(withTitle: String(localized: "Open \(app.name)"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = canRemember
        alert.suppressionButton?.title = isPrivate
            ? String(localized: "Allow for this private tab")
            : String(localized: "Always allow for this website")
        return alert
    }

    private static func open(_ url: URL) {
        if let openerForTesting {
            openerForTesting(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private nonisolated static func application(toOpen url: URL) async -> Match? {
        await Task.detached(priority: .userInitiated) {
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
            let bundle = Bundle(url: app)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? app.deletingPathExtension().lastPathComponent
            return Match(
                url: app,
                name: name,
                bundleIdentifier: bundle?.bundleIdentifier
            )
        }.value
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        if let presenterForTesting {
            return await presenterForTesting(alert)
        }
        guard let window else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
