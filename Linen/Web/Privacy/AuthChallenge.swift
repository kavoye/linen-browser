// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
enum AuthChallenge {
    enum Decision: Equatable {
        case evaluateServerTrust
        case useDefaultHandling
        case rejectProtectionSpace
        case promptForCredential
    }

    static func decision(
        for space: URLProtectionSpace,
        previousFailureCount: Int
    ) -> Decision {
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return .evaluateServerTrust
        }
        guard isPasswordBased(space.authenticationMethod) else {
            return .useDefaultHandling
        }
        guard previousFailureCount < 3 else {
            return .rejectProtectionSpace
        }
        return .promptForCredential
    }

    static func isPasswordBased(_ method: String) -> Bool {
        switch method {
        case NSURLAuthenticationMethodHTTPBasic,
             NSURLAuthenticationMethodHTTPDigest,
             NSURLAuthenticationMethodNTLM:
            return true
        default:
            return false
        }
    }

    static func requestCredential(
        for space: URLProtectionSpace,
        previousFailures: Int,
        in window: NSWindow?
    ) async -> URLCredential? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Sign in to \(space.host)")
        alert.informativeText = previousFailures > 0
            ? String(localized: "That username or password wasn’t accepted. Try again.")
            : realmDescription(for: space)
        alert.addButton(withTitle: String(localized: "Sign In"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let fields = NSStackView(views: [])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.alignment = .leading

        let user = NSTextField(string: "")
        user.placeholderString = String(localized: "Username")
        let password = NSSecureTextField(string: "")
        password.placeholderString = String(localized: "Password")
        for field in [user, password] as [NSTextField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
            fields.addArrangedSubview(field)
        }
        fields.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = user

        let response = await present(alert, in: window)
        guard response == .alertFirstButtonReturn, !user.stringValue.isEmpty else { return nil }
        return URLCredential(
            user: user.stringValue,
            password: password.stringValue,
            persistence: .forSession
        )
    }

    private static func realmDescription(for space: URLProtectionSpace) -> String {
        guard let realm = space.realm, !realm.isEmpty else {
            return String(localized: "This website is asking for a username and password.")
        }
        let trimmed = realm.count > 80 ? String(realm.prefix(80)) + "…" : realm
        return String(localized: "This website is asking for a username and password for “\(trimmed)”.")
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
