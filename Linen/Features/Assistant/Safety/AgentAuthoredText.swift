// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

@MainActor
enum AgentAuthoredText {
    private struct Record {
        weak var webView: WKWebView?
        let host: String?
    }

    private static var records: [ObjectIdentifier: Record] = [:]

    static func record(in webView: WKWebView) {
        records = records.filter { $0.value.webView != nil }
        records[ObjectIdentifier(webView)] = Record(webView: webView, host: webView.url?.host())
    }

    static func isPresent(in webView: WKWebView) -> Bool {
        guard let record = records[ObjectIdentifier(webView)] else { return false }
        return record.webView === webView && record.host == webView.url?.host()
    }

    static func clear(in webView: WKWebView) {
        records.removeValue(forKey: ObjectIdentifier(webView))
    }
}
