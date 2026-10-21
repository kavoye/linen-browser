// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BrowserTab {
    func connectLinkMenu(of view: TabWebView?) {
        view?.onOpenLinkInNewWindow = { [weak self] url, isPrivate in
            self?.events.onOpenInNewWindow?(url, isPrivate, true)
        }
        view?.onOpenLinkInNewTab = { [weak self] url in
            guard let open = self?.events.onOpenInNewTab else { return false }
            open(url, false)
            return true
        }
        view?.onSearchSelection = { [weak self] url in
            self?.events.onOpenInNewTab?(url, true)
        }
    }

    static func disconnectLinkMenu(of view: TabWebView?) {
        view?.onOpenLinkInNewWindow = nil
        view?.onOpenLinkInNewTab = nil
        view?.onSearchSelection = nil
    }
}
