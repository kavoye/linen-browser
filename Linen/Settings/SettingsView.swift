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

    var onRoute: ((SettingsCategory) -> Void)?

    func select(_ category: SettingsCategory) {
        query = ""
        highlightTask?.cancel()
        highlight = nil
        self.category = category
        onRoute?(category)
    }

    func open(_ entry: SettingsEntry) {
        highlightTask?.cancel()
        highlight = entry.id
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.highlight = nil
        }
        category = entry.category
        onRoute?(entry.category)
    }

    func reveal(_ anchor: String) {
        guard let entry = SettingsIndex.all.first(where: { $0.id == anchor }) else { return }
        open(entry)
    }

    func adopt(_ category: SettingsCategory) {
        guard self.category != category else { return }
        self.category = category
        query = ""
    }
}

struct SettingsView: View {
    let coordinator: AppCoordinator
    let workspace: SettingsWorkspace

    @State private var surfaceWidth: CGFloat = SettingsMetrics.twoColumnMinWidth

    private var showsNamedNavigator: Bool {
        surfaceWidth >= SettingsMetrics.twoColumnMinWidth
    }

    private var address: String {
        coordinator.browser.tabs.first { $0.internalPage == .settings }?.urlString ?? ""
    }

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
                selection: Binding(
                    get: { workspace.category },
                    set: { workspace.select($0) }
                ),
                query: $workspace.query,
                profileName: coordinator.profiles.current.name,
                profileSymbol: coordinator.profiles.current.symbol,
                profileTint: coordinator.profiles.current.color.tint,
                badges: badges,
                showsNames: showsNamedNavigator,
                onOpen: workspace.open
            )
            .frame(width: showsNamedNavigator
                ? SettingsMetrics.navWidth
                : SettingsMetrics.navIconsWidth)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(SettingsMetrics.hairline)
                    .frame(width: 1)
            }

            SettingsDetail(
                category: workspace.category,
                coordinator: coordinator,
                intelligence: workspace.intelligence,
                highlight: workspace.highlight,
                isCompact: !showsNamedNavigator,
                onReveal: workspace.reveal
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            surfaceWidth = width
        }
        .onChange(of: address, initial: true) { _, _ in
            workspace.adopt(SystemPages.settingsCategory(of: address) ?? .general)
        }
    }
}

private struct SettingsDetail: View {
    let category: SettingsCategory
    let coordinator: AppCoordinator
    let intelligence: IntelligenceViewModel
    let highlight: String?
    let isCompact: Bool
    let onReveal: (String) -> Void

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
                .padding(.horizontal, isCompact
                    ? SettingsMetrics.compactPageInset
                    : SettingsMetrics.pageInset)
                .padding(.top, 34)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .environment(\.settingsHighlight, highlight)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == SettingsIndex.linkScheme, let anchor = url.host() else {
                    return .systemAction
                }
                onReveal(anchor)
                return .handled
            })
            .environment(\.settingsIsCompact, isCompact)
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
        SettingsPageHeader(title: "Extensions", caption: summary)

        SettingsSection(
            title: "Chrome extensions",
            symbol: "puzzlepiece.extension",
            accessory: {
                SettingsButton(title: "Chrome Web Store", symbol: "arrow.up.forward") {
                    coordinator.openNewTab(
                        url: URL(string: "https://chromewebstore.google.com/category/extensions")
                    )
                }
                .help("Browse extensions to install")
            },
            content: {
                ExtensionsSettingsCard(coordinator: coordinator)
            }
        )
        .settingsAnchor("extensions.installed")

        SafariExtensionsSettingsCard(coordinator: coordinator)
    }

    private var summary: LocalizedStringResource {
        let total = installed.count + coordinator.extensions.systemExtensions.count
        let running = enabled + coordinator.extensions.systemExtensions.count(where: \.enabled)
        if total == 0 {
            return "No extensions yet."
        }
        if running == total {
            return "\(total) extensions, all running."
        }
        return "\(total) extensions, \(running) running."
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
                DetailRow(
                    title: "Send feedback",
                    caption: "Opens a new issue on Linen’s repository."
                ) {
                    SettingsButton(title: "Send…") {
                        coordinator.openNewTab(url: UpdateFeed.newIssueURL)
                    }
                }
                .settingsAnchor("about.report")

                RowSeparator()

                DrillInRow(
                    title: "Acknowledgements",
                    caption: "The open source packages Linen is built with."
                ) {
                    readingAcknowledgements = true
                }
            }
            .settingsAnchor("about.acknowledgements")
        }
    }
}
