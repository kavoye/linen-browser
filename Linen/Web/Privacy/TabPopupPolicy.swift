// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class TabPopupPolicy {
    private let store: SitePermissions

    init(store: SitePermissions = .shared) {
        self.store = store
    }

    private(set) var origin = ""

    private(set) var blocked: URL?

    var effective: PopupPolicy {
        if !origin.isEmpty, let recorded = store.popups(for: origin) {
            return recorded
        }
        return BrowserSettings.shared.blocksPopups ? .blockAndNotify : .allow
    }

    func pageChanged(url: URL?) -> Bool {
        let next = SystemPages.isSystem(url) ? "" : SitePermissions.origin(for: url)
        guard next != origin else { return false }
        origin = next
        blocked = nil
        return true
    }

    func note(_ url: URL?) {
        guard effective == .blockAndNotify else { return }
        blocked = url
    }

    func clear() {
        blocked = nil
    }
}

extension BrowserTab {
    func applySitePopups() {
        guard popups.pageChanged(url: webView.url) else { return }
        refreshPopupPolicy()
    }

    func refreshPopupPolicy() {
        guard isMaterialised else { return }
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = !popups.effective.blocks
    }
}
