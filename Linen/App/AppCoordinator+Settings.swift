// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AppCoordinator {
    func openSettings(_ category: SettingsCategory? = nil) {
        showBrowser()
        let tab = browser.showSettings()
        guard let category else { return }
        route(to: category, in: tab)
    }

    func routeSettings(to category: SettingsCategory, path: [String] = [], isBack: Bool = false) {
        guard let tab = browser.tabs.first(where: { $0.internalPage == .settings }) else { return }
        let url = SystemPages.settingsURL(category, path: path)
        if isBack, tab.backList.last?.url == url {
            tab.goBack()
            return
        }
        route(to: url, in: tab)
    }

    private func route(to category: SettingsCategory, in tab: BrowserTab) {
        route(to: SystemPages.settingsURL(category), in: tab)
    }

    private func route(to url: URL, in tab: BrowserTab) {
        guard tab.urlString != url.absoluteString else { return }
        tab.load(url)
        tab.urlString = url.absoluteString
        tab.title = BrowserTab.InternalPage.settings.title
    }

    var isShowingSettings: Bool {
        browser.activeTab?.internalPage == .settings
    }
}
