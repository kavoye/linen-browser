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
        isDefault ? "Links from other apps open in Linen." : "Links from other apps open in another browser."
    }

    private var defaultBrowserButton: LocalizedStringResource {
        isDefault ? "Default" : "Set as Default…"
    }

    private var mediaFootnote: LocalizedStringResource? {
        guard settings.showsVideoInPlayer else { return nil }
        return "Automatic Picture in Picture is off while \"Show video in the player\" is on in Experiments."
    }

    var body: some View {
        SettingsPageHeader(title: "General")

        SettingsSection(
            title: "Startup & data",
            symbol: "arrow.up.forward.app",
            footnote: "Export your bookmarks as an HTML file in the other browser first."
        ) {
            DetailRow(
                title: "Default web browser",
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

            RowSeparator()

            BookmarkImportRow(
                browser: coordinator.browser,
                caption: "Import an HTML file from Safari, Chrome, Firefox, or Edge."
            )
            .settingsAnchor("general.import")
        }
        .task { isDefault = DefaultBrowser.isCurrent }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isCurrent
        }

        if handedOver {
            Footnote("System Settings is open. Choose Linen under \"Default web browser.\"")
        } else if askedToBeDefault, !isDefault {
            Footnote("If no panel appeared, set it in System Settings under Desktop & Dock.")
        }

        SettingsSection(title: "Tabs", symbol: "rectangle.on.rectangle") {
            DetailRow(
                title: "Sleep inactive tabs",
                caption: "When your Mac runs low on memory, inactive tabs unload. They reload when you open them."
            ) {
                SettingsToggle($settings.sleepsInactiveTabs)
            }
            .settingsAnchor("general.sleepTabs")

            RowSeparator()

            DetailRow(
                title: "Archive tabs after",
                caption: "Unpinned tabs you haven’t used close automatically. Find them again with ⌘K."
            ) {
                SettingsMenu(
                    options: TabArchiveDelay.allCases.map { .init(value: $0, label: String(localized: $0.label)) },
                    selection: $settings.archiveTabsAfter
                )
            }
            .settingsAnchor("general.archiveTabs")
        }

        SettingsSection(title: "Browsing", symbol: "cursorarrow.rays", footnote: mediaFootnote) {
            DetailRow(
                title: "Show status bar",
                caption: "Shows where a link goes at the bottom of the window."
            ) {
                SettingsToggle($settings.showsLinkPreview)
            }
            .settingsAnchor("general.linkPreview")

            RowSeparator()

            DetailRow(
                title: "Show full website address",
                caption: "Shows the whole address instead of just the website name."
            ) {
                SettingsToggle($settings.showsFullAddress)
            }
            .settingsAnchor("general.fullAddress")

            RowSeparator()

            DetailRow(
                title: "Show media player",
                caption: "Pause or skip audio and video playing in any tab."
            ) {
                SettingsToggle($settings.showsMediaPlayer)
            }
            .settingsAnchor("general.mediaPlayer")

            RowSeparator()

            DetailRow(
                title: "Automatic Picture in Picture",
                caption: "Video keeps playing in a floating window when you leave its tab."
            ) {
                SettingsToggle($settings.automaticPictureInPicture)
            }
            .settingsAnchor("general.automaticPiP")
            .disabled(settings.showsVideoInPlayer)
        }
    }

    private func becomeDefault() {
        askedToBeDefault = true
        Task {
            handedOver = await DefaultBrowser.request() == .handedOverToSystemSettings
            isDefault = DefaultBrowser.isCurrent
        }
    }
}
