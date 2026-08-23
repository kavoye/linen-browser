// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsWorkspace {
    var category = SettingsCategory.general
    var query = ""
    var highlight: String?

    let intelligence: IntelligenceViewModel

    @ObservationIgnored private var highlightTask: Task<Void, Never>?

    init(coordinator: AppCoordinator) {
        intelligence = IntelligenceViewModel(
            onConfigurationChanged: coordinator.configureEngines
        )
    }

    func select(_ category: SettingsCategory) {
        self.category = category
        query = ""
        highlightTask?.cancel()
        highlight = nil
    }

    func open(_ entry: SettingsEntry) {
        category = entry.category
        highlightTask?.cancel()
        highlight = entry.id
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.highlight = nil
        }
    }
}

struct SettingsView: View {
    let coordinator: AppCoordinator
    let workspace: SettingsWorkspace

    private var badges: [SettingsCategory: String] {
        var badges: [SettingsCategory: String] = [:]
        let installed = coordinator.extensions.installed.count
        if installed > 0 {
            badges[.extensions] = "\(installed)"
        }
        let active = coordinator.browser.downloads.activeCount
        if active > 0 {
            badges[.downloads] = "\(active)"
        }
        return badges
    }

    var body: some View {
        @Bindable var workspace = workspace

        HStack(spacing: 0) {
            SettingsNavigator(
                selection: $workspace.category,
                query: $workspace.query,
                profileName: coordinator.profiles.current.name,
                profileSymbol: coordinator.profiles.current.symbol,
                profileTint: coordinator.profiles.current.color.tint,
                badges: badges,
                onOpen: workspace.open
            )
            .frame(width: SettingsMetrics.navWidth)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(SettingsMetrics.hairline)
                    .frame(width: 1)
            }

            SettingsDetail(
                category: workspace.category,
                coordinator: coordinator,
                intelligence: workspace.intelligence,
                highlight: workspace.highlight
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.settingsDestination, initial: true) { _, destination in
            guard let destination else { return }
            workspace.select(destination)
            coordinator.settingsDestination = nil
        }
    }
}

private struct SettingsDetail: View {
    let category: SettingsCategory
    let coordinator: AppCoordinator
    let intelligence: IntelligenceViewModel
    let highlight: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                    switch category {
                    case .general:
                        GeneralSettings(coordinator: coordinator, settings: coordinator.settings)
                    case .search:
                        SearchSettings(coordinator: coordinator, settings: coordinator.settings)
                    case .appearance:
                        AppearanceSettings(coordinator: coordinator, settings: coordinator.settings)
                    case .provider:
                        AssistantSettings(model: intelligence, coordinator: coordinator)
                    case .profiles:
                        ProfileSettings(coordinator: coordinator)
                    case .privacy:
                        PrivacySettings(coordinator: coordinator, settings: coordinator.settings)
                    case .websites:
                        WebsiteSettings(
                            settings: coordinator.settings,
                            permissions: coordinator.browser.sitePermissions
                        )
                    case .downloads:
                        DownloadsSettings(coordinator: coordinator, settings: coordinator.settings)
                    case .extensions:
                        ExtensionsSettings(coordinator: coordinator)
                    case .advanced:
                        AdvancedSettings(settings: coordinator.settings)
                    case .experiments:
                        ExperimentsSettings(settings: coordinator.settings)
                    case .about:
                        AboutSettings(coordinator: coordinator, settings: coordinator.settings)
                    }
                }
                .frame(maxWidth: SettingsMetrics.detailWidth, alignment: .leading)
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.top, 34)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .environment(\.settingsHighlight, highlight)
            .onChange(of: highlight) { _, anchor in
                guard let anchor else { return }
                Task {
                    // Wait one runloop turn. `scrollTo` does nothing for an
                    // id that the same update is still building.
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(Theme.Motion.drift) {
                        proxy.scrollTo(anchor, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Pages

private struct ExtensionsSettings: View {
    let coordinator: AppCoordinator

    private var installed: [InstalledExtension] {
        coordinator.extensions.installed
    }

    private var enabled: Int {
        installed.filter(\.enabled).count
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsPageHeader(
                title: "Extensions",
                caption: summary
            )

            SettingsButton(title: "Chrome Web Store", symbol: "arrow.up.forward") {
                coordinator.openNewTab(url: URL(string: "https://chromewebstore.google.com/category/extensions"))
            }
            .help("Browse extensions to install")
        }

        ExtensionsSettingsCard(coordinator: coordinator)
            .settingsAnchor("extensions.installed")

        Footnote("On an extension’s page in the store, an Install button appears in the toolbar.")
    }

    private var summary: LocalizedStringResource {
        if installed.isEmpty {
            return "No extensions installed yet."
        }
        if enabled == installed.count {
            return "\(installed.count) installed, all running."
        }
        return "\(installed.count) installed, \(enabled) running."
    }
}

private struct AboutSettings: View {
    let coordinator: AppCoordinator
    @Bindable var settings: BrowserSettings

    @State private var readingAcknowledgements = false

    var body: some View {
        if readingAcknowledgements {
            AcknowledgementsPage(coordinator: coordinator) {
                readingAcknowledgements = false
            }
        } else {
            SettingsPageHeader(
                title: "Linen",
                detail: String(localized: "Version \(UpdateFeed.currentVersion)"),
                icon: NSApp.applicationIconImage
            )

            SettingsCard {
                UpdateRow(updates: coordinator.updates)
                RowSeparator()
                DetailRow(title: "Update channel", caption: settings.updateChannel.caption) {
                    SettingsMenu(
                        options: UpdateChannel.allCases.map {
                            .init(value: $0, label: String(localized: $0.label))
                        },
                        selection: $settings.updateChannel
                    )
                }
                .settingsAnchor("about.updates.channel")
            }
            .settingsAnchor("about.updates")

            SettingsCard {
                DetailRow(title: "Acknowledgements") {
                    SettingsButton(title: "Show") { readingAcknowledgements = true }
                }
            }
            .settingsAnchor("about.acknowledgements")
        }
    }
}
