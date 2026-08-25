// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct InternalPageSurface: View {
    let page: BrowserTab.InternalPage
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let settingsWorkspace: SettingsWorkspace

    var body: some View {
        switch page {
        case .settings:
            SettingsView(coordinator: coordinator, workspace: settingsWorkspace)
        case .history:
            HistoryView(browser: browser)
        case .downloads:
            DownloadsView(browser: browser)
        case .releaseNotes:
            ReleaseNotesView(browser: browser, notes: coordinator.releaseNotes)
        }
    }
}
