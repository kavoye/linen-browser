// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

struct TabSiteZoom {
    private(set) var changes = 0
    private var host = ""

    mutating func noteChange() {
        changes &+= 1
    }

    mutating func apply(to view: WKWebView, context: BrowserProfileContext) {
        let host = SystemPages.isSystem(view.url) ? "" : view.url?.host()?.lowercased() ?? ""
        guard host != self.host else { return }
        self.host = host
        let remembered = host.isEmpty ? nil : context.pageZoom.level(for: host)
        view.pageZoom = remembered ?? context.settings.pageZoom
        changes &+= 1
    }

    func record(from view: WKWebView, context: BrowserProfileContext, isPrivate: Bool) {
        guard !isPrivate, !host.isEmpty else { return }
        context.pageZoom.set(view.pageZoom, for: host, defaultZoom: context.settings.pageZoom)
    }
}
