// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    nonisolated static func contextLabel(_ reference: String) -> (title: String, host: String?, isActive: Bool) {
        var text = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var isActive = false
        if let arrow = text.range(of: "←") {
            isActive = text[arrow.upperBound...].contains("active")
            text = String(text[..<arrow.lowerBound])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if let dot = text.firstIndex(of: "."), Int(text[..<dot]) != nil {
            text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        var host: String?
        if text.hasSuffix(")"), let open = text.lastIndex(of: "("), open > text.startIndex {
            host = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return (text.isEmpty ? reference.lowercased() : text, host, isActive)
    }

    func readableSurface(named reference: String) -> (webView: WKWebView, note: String)? {
        if let webView = pageSurface(named: reference) {
            return (webView, "")
        }
        let needle = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scheme = URL(string: needle)?.scheme
        guard scheme != "http", scheme != "https", let active = browser.activeTab, onScreenTabs.contains(where: { $0.id == active.id }),
              !browser.tabs.contains(where: { $0.title.lowercased().contains(needle) || $0.urlString.lowercased().contains(needle) })
        else { return nil }
        return (active.webView, "No page matches “\(reference)”, so this is the active page, “\(active.title)”.\n")
    }

    func onScreenPageDenial(for reference: String) -> String {
        guard !browser.tabs.isEmpty else { return "No tab is open yet." }
        var titles = onScreenTabs.map(\.title)
        titles += mentionedTabs.map { "\($0.title) (mentioned)" }
        let listed = titles.joined(separator: " | ")
        guard !reference.isEmpty, !listed.isEmpty else { return "No tab is open yet." }
        let denial = "No page on screen or mentioned matches “\(reference)”. Readable: \(listed)"
        guard let url = URL(string: reference.trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return denial
        }
        return denial + ". To open this URL, call navigate with it, then read the page."
    }
}
