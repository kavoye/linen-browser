// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct DownloadsSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @State private var confirmingClear = false

    private var downloads: DownloadManager {
        coordinator.browser.downloads
    }

    private var finishedCount: Int {
        downloads.items.count { !$0.isRunning }
    }

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
        }

        SettingsSection(
            title: "Recent",
            symbol: "clock.arrow.circlepath",
            accessory: {
                if finishedCount > 0 {
                    SettingsButton(title: "Clear…", isDestructive: true) {
                        confirmingClear = true
                    }
                }
            },
            content: {
                if downloads.items.isEmpty {
                    DetailRow(caption: "No recent downloads.") {
                        EmptyView()
                    }
                } else {
                    ForEach(downloads.items.enumerated(), id: \.element.id) { index, item in
                        if index > 0 {
                            RowSeparator()
                        }
                        DownloadRow(item: item, downloads: downloads)
                    }
                }
            }
        )
        .settingsAnchor("downloads.list")
        .confirmationDialog(
            "Clear the download list?",
            isPresented: $confirmingClear
        ) {
            Button("Clear List", role: .destructive) { downloads.clearFinished() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(finishedCount) downloads will be removed from the list. The files stay in your Downloads folder.")
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

private struct DownloadRow: View {
    let item: DownloadManager.Item
    let downloads: DownloadManager

    var body: some View {
        DetailRow(verbatimTitle: item.filename, verbatimCaption: subtitle) {
            HStack(spacing: 8) {
                if item.isRunning {
                    if let fraction = item.fraction {
                        ProgressView(value: fraction)
                            .controlSize(.small)
                            .frame(width: 80)
                    } else {
                        Spinner(size: 12)
                            .foregroundStyle(.secondary)
                    }
                    IconButton(symbol: "xmark", help: "Stop") {
                        downloads.cancel(item)
                    }
                } else if item.state == .finished {
                    SettingsButton(title: "Open") { downloads.open(item) }
                    IconButton(symbol: "folder", help: "Show in Finder") {
                        downloads.revealInFinder(item)
                    }
                } else {
                    StatusDot(.attention, haloed: false)
                }
            }
        }
    }

    private var subtitle: String {
        guard !item.source.isEmpty else { return item.sizeSummary }
        return "\(item.sizeSummary) · from \(item.source)"
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
