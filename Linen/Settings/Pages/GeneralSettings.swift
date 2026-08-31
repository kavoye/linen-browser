// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GeneralSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @State private var isDefault = false
    @State private var askedToBeDefault = false
    @State private var handedOver = false

    private var defaultBrowserCaption: LocalizedStringResource {
        isDefault ? "Linen is your default browser." : "Linen isn’t your default browser."
    }

    private var defaultBrowserButton: LocalizedStringResource {
        isDefault ? "Default" : "Set as Default…"
    }

    private var mediaFootnote: LocalizedStringResource? {
        guard settings.showsVideoInPlayer else { return nil }
        return "Automatic Picture in Picture is off while “Show video in the player” is on in Experiments."
    }

    var body: some View {
        SettingsPageHeader(title: "General")

        SettingsSection(title: "New tabs", symbol: "rectangle.badge.plus") {
            OptionList(
                options: NewTabBehavior.allCases.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: settings.newTab,
                onSelect: { settings.newTab = $0 }
            )

            if settings.newTab == .homepage {
                RowSeparator()

                HomepageRow(coordinator: coordinator, settings: settings)
                    .settingsAnchor("general.homepage")
            }
            RowSeparator()

            DetailRow(
                title: "Sleep inactive tabs",
                caption: "Frees memory when the Mac runs low. Tabs reload when you return to them."
            ) {
                SettingsToggle($settings.sleepsInactiveTabs)
            }
            .settingsAnchor("general.sleepTabs")
        }
        .settingsAnchor("general.newTab")

        SettingsSection(title: "Default browser", symbol: "arrow.up.forward.app") {
            DetailRow(
                title: "Open links from other apps",
                caption: defaultBrowserCaption
            ) {
                SettingsButton(
                    title: defaultBrowserButton,
                    isProminent: !isDefault
                ) {
                    becomeDefault()
                }
                .disabled(isDefault)
            }
            .settingsAnchor("general.defaultBrowser")
        }
        .task { isDefault = DefaultBrowser.isCurrent }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isCurrent
        }

        if handedOver {
            Footnote("System Settings is open. Choose Linen under “Default web browser.”")
        } else if askedToBeDefault, !isDefault {
            Footnote("If no panel appeared, set it in System Settings under Desktop & Dock.")
        }

        SettingsSection(title: "Browsing", symbol: "cursorarrow.rays") {
            DetailRow(
                title: "Show link preview",
                caption: "Hold the pointer over a link to see its address at the bottom of the page."
            ) {
                SettingsToggle($settings.showsLinkPreview)
            }
            .settingsAnchor("general.linkPreview")
        }

        SettingsSection(title: "Media", symbol: "play.rectangle", footnote: mediaFootnote) {
            DetailRow(
                title: "Show media player",
                caption: "The sidebar shows what’s playing, so you can pause or skip from any tab."
            ) {
                SettingsToggle($settings.showsMediaPlayer)
            }
            .settingsAnchor("general.mediaPlayer")

            RowSeparator()

            DetailRow(
                title: "Automatic Picture in Picture",
                caption: "Video moves into a floating window when you leave its tab or switch to another app."
            ) {
                SettingsToggle($settings.automaticPictureInPicture)
            }
            .settingsAnchor("general.automaticPiP")
            .disabled(settings.showsVideoInPlayer)

            RowSeparator()

            DetailRow(
                title: "Show lyrics",
                caption: "Linen looks up lyrics on LRCLIB. Only the song and artist names leave your Mac, and never from a private tab."
            ) {
                SettingsToggle($settings.showsLyrics)
            }
            .settingsAnchor("general.lyrics")
        }

        ImportSection(coordinator: coordinator)
    }

    private func becomeDefault() {
        askedToBeDefault = true
        Task {
            handedOver = await DefaultBrowser.request() == .handedOverToSystemSettings
            isDefault = DefaultBrowser.isCurrent
        }
    }
}

private struct HomepageRow: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @FocusState private var focused: Bool

    private var currentPage: String? {
        let url = coordinator.browser.activeTab?.urlString ?? ""
        return url.isEmpty || url.hasPrefix("about:") ? nil : url
    }

    var body: some View {
        DetailRow(
            title: "Homepage",
            caption: "New tabs open with this page.",
            layout: .stacked
        ) {
            HStack(spacing: 8) {
                FieldChrome(isFocused: focused) {
                    TextField("", text: $settings.homepage)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .fieldPlaceholder(verbatim: "example.com", isShowing: settings.homepage.isEmpty)
                        .focused($focused)
                }

                if let currentPage {
                    SettingsButton(title: "Use This Page") {
                        settings.homepage = currentPage
                    }
                }

                if !settings.homepage.isEmpty {
                    IconButton(symbol: "xmark", help: "Clear") {
                        settings.homepage = ""
                        if settings.newTab == .homepage {
                            settings.newTab = .startPage
                        }
                    }
                }
            }
        }
    }
}

private struct ImportSection: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsSection(
            title: "Import",
            symbol: "square.and.arrow.down",
            footnote: "In the other browser, export your bookmarks to an HTML file first."
        ) {
            BookmarkImportRow(
                browser: coordinator.browser,
                caption: "An HTML file exported from Safari, Chrome, Firefox, or Edge."
            )
            .settingsAnchor("general.import")
        }
    }
}
