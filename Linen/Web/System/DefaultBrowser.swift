// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os

/// http and https are protected schemes. LaunchServices rebinds them only
/// for a signed and notarised app, so the fallback opens System Settings.
enum DefaultBrowser {
    enum Outcome {
        case answered
        case handedOverToSystemSettings
    }

    static var isCurrent: Bool {
        isHandler(of: "https://example.com")
    }

    @MainActor
    static func request() async -> Outcome {
        let workspace = NSWorkspace.shared
        let us = Bundle.main.bundleURL
        do {
            try await workspace.setDefaultApplication(at: us, toOpenURLsWithScheme: "https")
            if !isHandler(of: "http://example.com") {
                try await workspace.setDefaultApplication(at: us, toOpenURLsWithScheme: "http")
            }
            return .answered
        } catch {
            Pipeline.log.error("Default browser request refused: \(error, privacy: .public)")
            openSystemSettings()
            return .handedOverToSystemSettings
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func isHandler(of probe: String) -> Bool {
        guard let url = URL(string: probe),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return false }
        return handler.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }
}
