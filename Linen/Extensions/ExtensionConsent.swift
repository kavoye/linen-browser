// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum ExtensionConsent {
    static func hostSummary(for patterns: Set<WKWebExtension.MatchPattern>) -> [String] {
        var reachesEverything = false
        var hosts: Set<String> = []

        for pattern in patterns {
            let host = pattern.host ?? ""
            if pattern.matchesAllHosts || host == "*" || host.isEmpty {
                reachesEverything = true
                continue
            }
            hosts.insert(host.hasPrefix("*.") ? String(host.dropFirst(2)) : host)
        }
        if reachesEverything {
            return [String(localized: "every website you visit")]
        }
        return hosts.sorted()
    }

    static func permissionSummary(for permissions: Set<WKWebExtension.Permission>) -> [String] {
        let plain: [String: String] = [
            "tabs": String(localized: "See the addresses and titles of your open tabs"),
            "history": String(localized: "Read your browsing history"),
            "cookies": String(localized: "Read and change cookies, including sign-in cookies"),
            "downloads": String(localized: "Manage your downloads"),
            "clipboardRead": String(localized: "Read your clipboard"),
            "clipboardWrite": String(localized: "Write to your clipboard"),
            "webRequest": String(localized: "Watch every network request the browser makes"),
            "declarativeNetRequest": String(localized: "Block and rewrite network requests"),
            "nativeMessaging": String(localized: "Talk to apps outside the browser"),
            "management": String(localized: "Manage your other extensions"),
            "proxy": String(localized: "Route your traffic through a proxy"),
            "debugger": String(localized: "Attach a debugger to pages"),
            "geolocation": String(localized: "See your location"),
        ]
        return permissions
            .compactMap { plain[$0.rawValue] }
            .sorted()
    }

    static func confirmInstall(
        name: String,
        permissions: Set<WKWebExtension.Permission>,
        matchPatterns: Set<WKWebExtension.MatchPattern>,
        unsupported: ExtensionCompatibility.Report = ExtensionCompatibility.Report(),
        in window: NSWindow?
    ) async -> Bool {
        await present(
            title: String(localized: "Install “\(name)”?"),
            body: body(
                hosts: hostSummary(for: matchPatterns),
                abilities: permissionSummary(for: permissions),
                unsupported: unsupported
            ),
            confirmTitle: String(localized: "Install"),
            in: window
        )
    }

    static func confirmRuntimeGrant(
        name: String,
        permissions: Set<WKWebExtension.Permission>,
        matchPatterns: Set<WKWebExtension.MatchPattern>,
        in window: NSWindow?
    ) async -> Bool {
        await present(
            title: String(localized: "“\(name)” wants more access"),
            body: body(
                hosts: hostSummary(for: matchPatterns),
                abilities: permissionSummary(for: permissions)
            ),
            confirmTitle: String(localized: "Allow"),
            in: window
        )
    }

    static func confirmRuntimeURLAccess(
        name: String,
        urls: Set<URL>,
        in window: NSWindow?
    ) async -> Bool {
        let hosts = Set(urls.compactMap { $0.host() }).sorted()
        return await present(
            title: String(localized: "“\(name)” wants more access"),
            body: body(hosts: hosts, abilities: []),
            confirmTitle: String(localized: "Allow"),
            in: window
        )
    }

    private static func present(
        title: String,
        body: String,
        confirmTitle: String,
        in window: NSWindow?
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.accessoryView = widthGuide()
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        guard let window else { return alert.runModal() == .alertFirstButtonReturn }
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .alertFirstButtonReturn
    }

    private static func widthGuide() -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 0))
    }

    static func body(
        hosts: [String],
        abilities: [String],
        unsupported: ExtensionCompatibility.Report = ExtensionCompatibility.Report()
    ) -> String {
        var lines: [String] = []
        if !hosts.isEmpty {
            lines.append(String(localized: "Read and change your data on:"))
            lines.append(contentsOf: hosts.prefix(8).map { "  • \($0)" })
            if hosts.count > 8 {
                let remainder = hosts.count - 8
                lines.append("  • " + String(localized: "and \(remainder) more"))
            }
        }
        if !abilities.isEmpty {
            if !lines.isEmpty {
                lines.append("")
            }
            lines.append(String(localized: "The extension will also be able to:"))
            lines.append(contentsOf: abilities.map { "  • \($0)" })
        }
        if lines.isEmpty {
            lines.append(String(localized: "This extension asks for no special access."))
        }
        if !unsupported.isEmpty {
            let summaries = unsupported.summaries
            lines.append("")
            lines.append(String(localized: "WebKit doesn’t provide some of what this extension uses, so parts of it may not work:"))
            lines.append(contentsOf: summaries.prefix(5).map { "  • \($0)" })
            if summaries.count > 5 {
                let remainder = summaries.count - 5
                lines.append("  • " + String(localized: "and \(remainder) more"))
            }
        }
        return lines.joined(separator: "\n")
    }
}
