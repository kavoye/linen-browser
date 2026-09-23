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
        isDefault ? "Linen is your default browser." : "Linen isn't your default browser."
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

        SettingsSection(title: "Tabs", symbol: "rectangle.on.rectangle") {
            DetailRow(
                title: "Sleep inactive tabs",
                caption: "When your Mac runs low on memory, inactive tabs unload. They reload when you open them."
            ) {
                SettingsToggle($settings.sleepsInactiveTabs)
            }
            .settingsAnchor("general.sleepTabs")
        }

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
            Footnote("System Settings is open. Choose Linen under \"Default web browser.\"")
        } else if askedToBeDefault, !isDefault {
            Footnote("If no panel appeared, set it in System Settings under Desktop & Dock.")
        }

        SettingsSection(title: "Browsing", symbol: "cursorarrow.rays") {
            DetailRow(
                title: "Show link address",
                caption: "Show a link's address at the bottom of the page when you point at it."
            ) {
                SettingsToggle($settings.showsLinkPreview)
            }
            .settingsAnchor("general.linkPreview")
        }

        SettingsSection(title: "Media", symbol: "play.rectangle", footnote: mediaFootnote) {
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

            RowSeparator()

            DetailRow(
                title: "Show lyrics",
                caption: "Send the song and artist to LRCLIB to find lyrics. Private tabs don't send song details."
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

private struct ImportSection: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsSection(
            title: "Import",
            symbol: "square.and.arrow.down",
            footnote: "Export your bookmarks as an HTML file in the other browser first."
        ) {
            BookmarkImportRow(
                browser: coordinator.browser,
                caption: "Import an HTML file from Safari, Chrome, Firefox, or Edge."
            )
            .settingsAnchor("general.import")
        }
    }
}
