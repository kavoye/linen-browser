// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct DownloadsPreview: View {
    let downloads: DownloadManager
    let select: (DownloadManager.Item) -> Void

    static let limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(downloads.items.prefix(Self.limit).reversed())) { item in
                DownloadsPreviewRow(item: item, downloads: downloads) {
                    select(item)
                }
            }
        }
        .padding(PopoverMenuRow<EmptyView>.inset)
        .frame(width: 268)
        .chromePopoverAppearance()
    }
}

private struct DownloadsPreviewRow: View {
    let item: DownloadManager.Item
    let downloads: DownloadManager
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DownloadThumbnail(item: item, size: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.filename)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    subtitle
                        .font(Theme.Font.label)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverBackground(
                isActive: hovering,
                in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }

    private static var rowRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.systemPopover, inset: PopoverMenuRow<EmptyView>.inset)
    }

    @ViewBuilder private var menu: some View {
        if item.state == .finished {
            Button("Open", action: action)
            Button("Show in Finder") { downloads.revealInFinder(item) }
        }
        if item.isRunning {
            Button("Stop") { downloads.cancel(item) }
        }
        if downloads.canResume(item) {
            Button("Resume") { downloads.resume(item) }
        }
        if !item.isRunning {
            Divider()
            Button("Remove from List", role: .destructive) { downloads.remove(item) }
        }
    }

    private var subtitle: Text {
        switch item.state {
        case .finished:
            Text(item.started, format: .relative(presentation: .named))
        case .running:
            Text(verbatim: item.sizeSummary)
        case .interrupted(let why), .failed(let why):
            Text(verbatim: why)
        case .cancelled:
            Text("Canceled")
        }
    }
}
