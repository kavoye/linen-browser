// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
enum AgentActionConsent {
    enum Decision {
        case allowOnce
        case allowAlways
        case decline
    }

    @TaskLocal static var decisionForTesting: Stub?
    @TaskLocal static var scopedPolicy: AgentActionPolicy?
    @TaskLocal static var externalClientName: String?

    struct Stub: @unchecked Sendable {
        let decide: (String, SensitiveAction.Category, String?) -> Decision

        init(_ decide: @escaping (String, SensitiveAction.Category, String?) -> Decision) {
            self.decide = decide
        }
    }

    static func permit(
        label: String,
        category: SensitiveAction.Category,
        host: String?,
        authoredByAI: Bool = false,
        policy: AgentActionPolicy = .shared
    ) async -> Bool {
        let policy = scopedPolicy ?? policy
        if policy.isAlwaysAllowed(category, host: host) {
            return true
        }

        if let stub = decisionForTesting {
            switch stub.decide(label, category, host) {
            case .allowOnce:
                return true
            case .allowAlways:
                policy.allowAlways(category, host: host)
                return true
            case .decline:
                return false
            }
        }

        switch await ask(label: label, category: category, host: host, authoredByAI: authoredByAI) {
        case .allowOnce:
            return true
        case .allowAlways:
            policy.allowAlways(category, host: host)
            return true
        case .decline:
            return false
        }
    }

    /// A test bundle has nobody to answer a sheet, and `runModal()` hangs the
    /// run rather than failing it. A gate that cannot ask denies.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func ask(
        label: String,
        category: SensitiveAction.Category,
        host: String?,
        authoredByAI: Bool = false
    ) async -> Decision {
        guard !isRunningTests, !Task.isCancelled else { return .decline }
        let site = AgentActionPolicy.normalizedHost(host)

        let alert = NSAlert()
        // Localize each heading where it is written. A ternary of literals puts
        // only the first in the catalog.
        alert.messageText = site.map { String(localized: "Allow “\(label)” on \($0)?") }
            ?? String(localized: "Allow “\(label)”?")
        alert.informativeText = body(
            label: label,
            category: category,
            site: site,
            authoredByAI: authoredByAI
        )
        if let externalClientName {
            alert.informativeText = String(localized: "Requested by the external connection “\(externalClientName)”.")
                + "\n\n" + alert.informativeText
        }

        alert.addButton(withTitle: String(localized: "Allow Once"))
        if let site {
            let title = externalClientName == nil
                ? String(localized: "Always Allow on \(site)")
                : String(localized: "Allow on \(site) for This Connection")
            alert.addButton(withTitle: title)
        }
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if window == nil {
            NSApp.activate(ignoringOtherApps: true)
        }

        let response: NSApplication.ModalResponse
        if let window {
            response = await withTaskCancellationHandler {
                guard !Task.isCancelled else { return .abort }
                return await withCheckedContinuation { continuation in
                    alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
            } onCancel: {
                Task { @MainActor in window.endSheet(alert.window, returnCode: .abort) }
            }
        } else {
            guard externalClientName == nil else { return .decline }
            response = alert.runModal()
        }

        guard !Task.isCancelled else { return .decline }

        switch response {
        case .alertFirstButtonReturn:
            return .allowOnce
        case .alertSecondButtonReturn:
            return site == nil ? .decline : .allowAlways
        default:
            return .decline
        }
    }

    static func body(
        label: String,
        category: SensitiveAction.Category,
        site: String?,
        authoredByAI: Bool = false
    ) -> String {
        let location = site.map { String(localized: "on \($0)") } ?? String(localized: "on this page")
        let stakes = String(localized: """
            The assistant wants to click “\(label)” \(location). This \(String(localized: category.consequence)) \
            and usually can’t be undone.
            """)
        let injection = String(localized: """
            Webpages can carry hidden instructions aimed at the assistant. Allow this only if \
            it’s what you asked for.
            """)

        guard authoredByAI, category == .publication else {
            return stakes + "\n\n" + injection
        }

        let authored = String(localized: """
            The text in this form was written by AI, not by you. Publishing it puts \
            AI-generated text out under your name.
            """)
        return stakes + "\n\n" + authored + "\n\n" + injection
    }
}
