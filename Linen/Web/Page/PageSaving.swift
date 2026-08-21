// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum PageSaving {
    static let archiveType = UTType("com.apple.webarchive") ?? .data

    static func begin(for webView: WKWebView) {
        guard let window = webView.window, !(webView.superview is WebViewParkingShelf) else { return }

        let panel = NSSavePanel()
        panel.title = String(localized: "Save Page As")
        panel.allowedContentTypes = [archiveType]
        panel.nameFieldStringValue = filename(for: webView)
        panel.directoryURL = BrowserSettings.shared.downloadFolder
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            write(webView, to: url, in: window)
        }
    }

    private static func write(_ webView: WKWebView, to url: URL, in window: NSWindow) {
        Task {
            do {
                let data = try await withCheckedThrowingContinuation { continuation in
                    webView.createWebArchiveData { continuation.resume(with: $0) }
                }
                try data.write(to: url, options: .atomic)
            } catch {
                report(error, in: window)
            }
        }
    }

    private static func report(_ error: any Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The page couldn’t be saved.")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        alert.beginSheetModal(for: window)
    }

    static func filename(for webView: WKWebView) -> String {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = webView.url?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        let stem = title.isEmpty ? host : title
        let safe = DownloadManager.safeFilename(stem.isEmpty ? String(localized: "Untitled") : stem)
        return "\(safe).\(archiveType.preferredFilenameExtension ?? "webarchive")"
    }
}
