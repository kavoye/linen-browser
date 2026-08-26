// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PrivacySettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @State private var isClearing = false
    @State private var cleared = false
    @State private var siteCount: Int?
    @State private var showingWebsiteData = false

    private var pageCount: Int {
        coordinator.browser.history.count
    }

    var body: some View {
        if showingWebsiteData {
            WebsiteDataPage { showingWebsiteData = false }
        } else {
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        SettingsPageHeader(title: "Privacy")

        SettingsCard {
            DetailRow(title: "Block known trackers") {
                SettingsToggle($settings.blocksTrackers)
            }
            .settingsAnchor("privacy.trackers")

            RowSeparator()

            DetailRow(
                title: "Clear browsing data",
                caption: "History, cookies, and cached files, over a chosen time range."
            ) {
                HStack(spacing: 10) {
                    if isClearing {
                        Spinner(size: 12)
                            .foregroundStyle(.secondary)
                    } else if cleared {
                        HStack(spacing: 6) {
                            StatusDot(.ready, haloed: false)
                            Text("Done")
                        }
                        .font(Theme.Font.label)
                        .foregroundStyle(.tertiary)
                    }

                    SettingsButton(title: "Clear…", isDestructive: true, symbol: "trash") {
                        Task { await clear() }
                    }
                    .disabled(isClearing)
                }
            }
            .settingsAnchor("privacy.clear")

            RowSeparator()

            DetailRow(
                title: "Clear on quit",
                caption: "Cookies, site data, and cached files, every time Linen closes."
            ) {
                SettingsToggle($settings.clearsDataOnQuit)
            }
            .settingsAnchor("privacy.quit")
        }

        SettingsSection(title: "History and website data", symbol: "clock") {
            DetailRow(
                title: "Keep history for",
                caption: retentionCaption
            ) {
                SettingsMenu(
                    options: HistoryRetention.allCases.map { .init(value: $0, label: String(localized: $0.label)) },
                    selection: Binding(
                        get: { settings.historyRetention },
                        set: { retention in
                            settings.historyRetention = retention
                            coordinator.browser.history.prune(retention: retention)
                        }
                    )
                )
            }
            .settingsAnchor("privacy.history")

            RowSeparator()

            DrillInRow(title: "Website data", caption: siteSummary) {
                showingWebsiteData = true
            }
            .disabled((siteCount ?? 0) == 0)
            .settingsAnchor("privacy.storage")
        }
        .task {
            siteCount = await BrowsingData.siteCount()
        }
    }

    private var siteSummary: LocalizedStringResource {
        switch siteCount {
        case nil:
            "Counting…"
        case 0:
            "No website stores data."
        case let count?:
            "\(count) websites are storing data."
        }
    }

    private var retentionCaption: LocalizedStringResource {
        pageCount == 0
            ? "No pages recorded yet."
            : "\(pageCount) pages kept. Older pages are removed."
    }

    private func clear() async {
        guard let choice = await ConfirmAlert.clear(.privacy()) else { return }
        isClearing = true
        cleared = false
        await BrowsingData.clear(
            choice.kinds,
            range: choice.range,
            history: coordinator.browser.history,
            agent: coordinator.conversationLog,
            tabs: coordinator.browser.tabs
        )
        siteCount = await BrowsingData.siteCount()
        isClearing = false
        cleared = true
    }
}
