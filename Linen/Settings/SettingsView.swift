// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import Observation
import SwiftUI

struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var category = SettingsCategory.general
    @State private var query = ""
    @State private var intelligence: IntelligenceViewModel
    @State private var highlight: String?
    @State private var highlightTask: Task<Void, Never>?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _intelligence = State(wrappedValue: IntelligenceViewModel(
            onConfigurationChanged: coordinator.configureEngines
        ))
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
        VStack(spacing: 0) {
            SettingsTopBar(sidebar: coordinator.sidebar)

            Rectangle()
                .fill(Theme.Wash.hairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                SettingsNavigator(
                    selection: $category,
                    query: $query,
                    profileName: coordinator.profiles.current.name,
                    profileSymbol: coordinator.profiles.current.symbol,
                    profileTint: coordinator.profiles.current.color.tint,
                    badges: badges,
                    onOpen: open
                )

                detail
            }
        }
        .background(Theme.windowBackground)
        .onChange(of: coordinator.settingsDestination, initial: true) { _, destination in
            guard let destination else { return }
            category = destination
            query = ""
            coordinator.settingsDestination = nil
        }
    }

    private func open(_ entry: SettingsEntry) {
        category = entry.category
        highlightTask?.cancel()
        highlight = entry.id
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            highlight = nil
        }
    }

    private var detail: some View {
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
                    case .voice:
                        VoiceSettings(coordinator: coordinator)
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

// MARK: - Window chrome

private struct SettingsTopBar: View {
    let sidebar: SidebarLayout

    @Environment(\.windowControlsInset) private var windowControlsInset

    private var windowControlsPadding: CGFloat {
        SidebarMetrics.windowControlsPadding(
            isVisible: sidebar.isVisible,
            style: sidebar.style,
            windowControlsInset: windowControlsInset
        )
    }

    private var sidebarToggleHelp: LocalizedStringResource {
        sidebar.isVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    var body: some View {
        HStack(spacing: 8) {
            if SidebarTogglePlacement.inNavBar(isVisible: sidebar.isVisible, style: sidebar.style) {
                ToolbarButton(symbol: "sidebar.left", enabled: true, help: String(localized: sidebarToggleHelp)) {
                    if sidebar.isVisible {
                        sidebar.toggleVisible()
                    } else {
                        sidebar.show()
                    }
                }
                .onHover { if $0, !sidebar.isVisible { sidebar.isPeeking = true } }
                .contextMenu {
                    SidebarStyleMenuItems(sidebar: sidebar)
                }
            }

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.leading, windowControlsPadding)
        .frame(height: Theme.topBarHeight)
        .background { WindowDragArea() }
    }
}

// MARK: - Pages

private struct VoiceSettings: View {
    let coordinator: AppCoordinator

    @State private var talk = ActivationSettings.talk
    @State private var recording: String?

    var body: some View {
        SettingsPageHeader(
            title: "Voice",
            caption: "Choose how you speak to Linen and hear replies."
        )

        SettingsCard {
            DetailRow(
                title: "Read aloud",
                caption: "Speak answers as they arrive. Change the voice or speed in [System Settings](x-apple.systempreferences:com.apple.preference.universalaccess?TextToSpeech)."
            ) {
                SettingsToggle(Binding(
                    get: { !coordinator.isSpeechMuted },
                    set: { enabled in
                        if enabled == coordinator.isSpeechMuted {
                            coordinator.toggleSpeechMute()
                        }
                    }
                ))
            }
            .settingsAnchor("voice.readAloud")

            RowSeparator()

            DetailRow(
                title: "Push to talk",
                caption: "Hold while speaking. Release to send."
            ) {
                ShortcutRecorder(
                    id: "talk",
                    recording: $recording,
                    shortcut: talk,
                    defaultShortcut:
                        ActivationSettings.defaultTalk
                ) { recorded in
                    talk = recorded
                    ActivationSettings.talk = recorded
                    coordinator.reloadActivation()
                }
            }
            .settingsAnchor("voice.talk")
        }
        .onChange(of: recording) { _, listening in
            coordinator.setActivationSuspended(listening != nil)
        }
    }
}

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
