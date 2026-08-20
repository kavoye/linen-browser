// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct StartPageSections: View {
    let sections: [StartPageSectionSnapshot]
    let browser: BrowserModel
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 34) {
            ForEach(sections) { section in
                StartPageSectionView(
                    section: section,
                    browser: browser,
                    coordinator: coordinator
                )
            }
        }
    }
}

private struct StartPageSectionView: View {
    let section: StartPageSectionSnapshot
    let browser: BrowserModel
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch section {
            case .recentTasks(let traces):
                StartPageTaskSection(
                    traces: traces,
                    coordinator: coordinator
                )
            case .frequentSites(let sites):
                StartPageFrequentSitesSection(
                    sites: sites,
                    browser: browser,
                    settings: coordinator.settings
                )
            case .history(let entries):
                StartPageHistorySection(
                    entries: entries,
                    browser: browser,
                    coordinator: coordinator
                )
            case .downloads(let items):
                StartPageDownloadsSection(
                    items: items,
                    downloads: browser.downloads,
                    coordinator: coordinator
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StartPageTaskSection: View {
    let traces: [ConversationLog.TaskTrace]
    let coordinator: AppCoordinator

    var body: some View {
        StartPageSectionGroup(section: .recentTasks) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(traces) { trace in
                    StartPageTaskCard(
                        trace: trace,
                        action: {
                            Task { await coordinator.handleTypedUtterance(trace.prompt) }
                        },
                        onRemove: { coordinator.conversationLog.removeTrace(trace.id) }
                    )
                }
            }
        }
    }
}

private struct StartPageFrequentSitesSection: View {
    let sites: [StartPageSite]
    let browser: BrowserModel
    let settings: BrowserSettings

    var body: some View {
        StartPageSectionGroup(section: .frequentSites) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                ForEach(sites) { site in
                    StartPageSiteTile(
                        site: site,
                        action: { open(site.url) },
                        onRemove: { settings.hideFrequentSite(host: site.host) }
                    )
                }
            }
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        browser.ensureActiveTab().load(url)
    }
}

private struct StartPageHistorySection: View {
    let entries: [HistoryStore.Entry]
    let browser: BrowserModel
    let coordinator: AppCoordinator

    var body: some View {
        StartPageSectionGroup(section: .history) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    HistoryRow(
                        entry: entry,
                        action: { open(entry.url) },
                        onRemove: { browser.history.remove(entry) }
                    )
                }

                StartPageShowAllButton(count: browser.history.count) {
                    coordinator.showHistory()
                }
                .padding(.top, 4)
            }
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        browser.ensureActiveTab().load(url)
    }
}

private struct StartPageDownloadsSection: View {
    let items: [DownloadManager.Item]
    let downloads: DownloadManager
    let coordinator: AppCoordinator

    var body: some View {
        StartPageSectionGroup(section: .downloads) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    StartPageDownloadRow(item: item, downloads: downloads)
                }

                StartPageShowAllButton(count: downloads.items.count) {
                    coordinator.showDownloads()
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct StartPageSectionGroup<Content: View>: View {
    let section: StartPageSection
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(Theme.Font.micro)
                Text(section.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .kerning(0.4)
            }
            .foregroundStyle(.tertiary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
