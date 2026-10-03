// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct DownloadsSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    var body: some View {
        SettingsPageHeader(
            title: "Downloads",
            detail: settings.downloadFolder.abbreviatedForDisplay
        )

        SettingsCard {
            DetailRow(
                title: "Save files to"
            ) {
                HStack(spacing: 8) {
                    SettingsButton(title: "Choose…") { chooseFolder() }

                    if settings.downloadFolder != BrowserSettings.defaultDownloadFolder {
                        SettingsButton(title: "Reset") {
                            settings.downloadFolder = BrowserSettings.defaultDownloadFolder
                        }
                    }
                }
            }
            .settingsAnchor("downloads.folder")

            RowSeparator()

            DetailRow(title: "Ask where to save each file") {
                SettingsToggle($settings.asksWhereToSave)
            }
            .settingsAnchor("downloads.ask")

            RowSeparator()

            DetailRow(
                title: "Remove download list items",
                caption: "Downloaded files aren’t deleted."
            ) {
                SettingsMenu(
                    options: DownloadRetention.allCases.map {
                        .init(value: $0, label: String(localized: $0.label))
                    },
                    selection: $settings.downloadRetention
                )
            }
            .settingsAnchor("downloads.retention")
        }

        SettingsCard {
            DrillInRow(title: "Open downloads", symbol: "arrow.down") {
                coordinator.browser.showDownloads()
            }
            .settingsAnchor("downloads.list")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadFolder
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.downloadFolder = url
    }
}

extension URL {
    var abbreviatedForDisplay: String {
        let path = path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        guard path.hasPrefix(home) else { return path }
        return "~/" + path.dropFirst(home.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
