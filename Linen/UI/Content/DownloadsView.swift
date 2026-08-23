// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct DownloadsView: View {
    let browser: BrowserModel

    @State private var confirmingClear = false

    private var downloads: DownloadManager {
        browser.downloads
    }

    private var finishedCount: Int {
        downloads.items.count { !$0.isRunning }
    }

    var body: some View {
        DestinationPage {
            toolbar
        } content: {
            LazyVStack(alignment: .leading, spacing: 2) {
                if downloads.items.isEmpty {
                    Text("No recent downloads.")
                        .font(Theme.Font.row)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 28)
                } else {
                    ForEach(downloads.items) { item in
                        DownloadFileRow(item: item, downloads: downloads)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            DestinationTitle(title: "Downloads") {
                browser.dismissInternalPage(.downloads)
            }

            if !downloads.items.isEmpty {
                DestinationCount(count: downloads.items.count)
            }

            Spacer(minLength: 12)

            ToolbarChip(symbol: "folder", label: "Folder") {
                NSWorkspace.shared.open(BrowserSettings.shared.downloadFolder)
            }

            ToolbarChip(symbol: "trash", label: "Clear", isDestructive: true) {
                confirmingClear = true
            }
            .disabled(finishedCount == 0)
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
    }
}

private struct DownloadFileRow: View {
    let item: DownloadManager.Item
    let downloads: DownloadManager

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(item.state == .finished ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.filename)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)

                subtitle
                    .font(Theme.Font.label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if item.isRunning {
                if let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                        .frame(width: 90)
                } else {
                    Spinner(size: 12)
                        .foregroundStyle(.secondary)
                }
                ChromeIcon(symbol: "xmark", size: 9, weight: .bold, help: String(localized: "Stop")) {
                    downloads.cancel(item)
                }
            } else {
                if downloads.canResume(item) {
                    ChromeIcon(
                        symbol: "arrow.clockwise",
                        help: String(localized: "Resume")
                    ) {
                        downloads.resume(item)
                    }
                }

                if hovering {
                    if item.state == .finished {
                        ChromeIcon(symbol: "folder", help: String(localized: "Show in Finder")) {
                            downloads.revealInFinder(item)
                        }
                    }

                    CloseButton(help: String(localized: "Remove from List")) {
                        downloads.remove(item)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverBackground(
            isActive: hovering,
            in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
        )
        .contentShape(Rectangle())
        .help(item.stoppedReason ?? "")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .onTapGesture {
            guard item.state == .finished else { return }
            downloads.open(item)
        }
    }

    private var symbol: String {
        switch item.state {
        case .running:
            "arrow.down"
        case .finished:
            "doc"
        case .interrupted:
            "pause.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "slash.circle"
        }
    }

    private var subtitle: Text {
        switch item.state {
        case .failed(let why):
            Text(verbatim: why)
        case .cancelled:
            Text("Canceled")
        case .running, .finished, .interrupted:
            if item.source.isEmpty {
                Text(verbatim: item.sizeSummary)
            } else {
                Text("\(item.sizeSummary) · from \(item.source)")
            }
        }
    }
}
