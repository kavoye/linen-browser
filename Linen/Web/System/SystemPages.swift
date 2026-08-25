// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

/// The browser's own pages are addressable. Each one is a real navigation to a
/// `linen:` URL, so WebKit's back-forward list is the only history a tab keeps.
nonisolated enum SystemPages {
    static let scheme = "linen"

    static let startHost = "start"

    static let start = URL(string: "\(scheme)://\(startHost)")!

    static let startSymbol = "square.grid.2x2"

    @MainActor static func showsStartFace(_ tab: BrowserTab) -> Bool {
        tab.isShowingStartPage || tab.hasNoPageYet
    }

    static func isSystem(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    static func isStart(_ url: URL?) -> Bool {
        isSystem(url) && url?.host()?.lowercased() == startHost
    }

    static func names(_ url: URL?) -> Bool {
        isStart(url) || BrowserTab.InternalPage(url: url) != nil
    }

    @MainActor static func settingsURL(_ category: SettingsCategory) -> URL {
        let base = BrowserTab.InternalPage.settings.url
        return category == .general ? base : base.appending(path: category.rawValue)
    }

    @MainActor static func settingsCategory(of url: URL?) -> SettingsCategory? {
        guard BrowserTab.InternalPage(url: url) == .settings else { return nil }
        guard let slug = url?.pathComponents.first(where: { $0 != "/" }) else { return nil }
        return SettingsCategory(rawValue: slug)
    }

    @MainActor static func settingsCategory(of url: String) -> SettingsCategory? {
        settingsCategory(of: URL(string: url))
    }
}

extension BrowserTab.InternalPage {
    nonisolated var host: String {
        switch self {
        case .history:
            "history"
        case .downloads:
            "downloads"
        case .releaseNotes:
            "release-notes"
        case .settings:
            "settings"
        }
    }

    nonisolated var url: URL {
        URL(string: "\(SystemPages.scheme)://\(host)")!
    }

    nonisolated init?(url: URL?) {
        guard SystemPages.isSystem(url), let host = url?.host()?.lowercased() else { return nil }
        guard let match = Self.allCases.first(where: { $0.host == host }) else { return nil }
        self = match
    }
}

final class SystemPageSchemeHandler: NSObject, WKURLSchemeHandler {
    private nonisolated static let document = Data("""
        <!doctype html><html><head><meta charset="utf-8">\
        <meta name="color-scheme" content="light dark">\
        <title></title></head><body></body></html>
        """.utf8)

    nonisolated func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, SystemPages.names(url) else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: "text/html",
            expectedContentLength: Self.document.count,
            textEncodingName: "utf-8"
        )
        task.didReceive(response)
        task.didReceive(Self.document)
        task.didFinish()
    }

    nonisolated func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
