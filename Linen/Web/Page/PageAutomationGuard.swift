// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

struct PageAutomationGuard: Sendable {
    @TaskLocal static var current: Self?

    let documentURL: String
    let snapshot: String?
    let validate: @MainActor @Sendable () -> Bool

    static var allowsExecution: Bool {
        guard !Task.isCancelled else { return false }
        return current?.validate() ?? true
    }

    static var world: WKContentWorld {
        .defaultClient
    }

    static var scriptCheck: String {
        guard let current,
              let url = encode(current.documentURL)
        else { return "" }
        var condition = "window.location.href !== \(url)"
        if let snapshot = current.snapshot.flatMap(encode) {
            condition += " || window.__linenSnapshot !== \(snapshot)"
        }
        return "if (\(condition)) { return JSON.stringify({ stale: true }); }\n"
    }

    static func withCurrentDocument(in view: WKWebView, operation: () async -> String) async -> String {
        guard allowsExecution else { return PageDriver.staleMessage }
        guard let prior = current else { return await operation() }
        let updated = Self(documentURL: view.url?.absoluteString ?? prior.documentURL,
                           snapshot: nil, validate: prior.validate)
        return await $current.withValue(updated) { await operation() }
    }

    private static func encode(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
