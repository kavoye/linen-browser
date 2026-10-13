// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct WatchesPanelSurface: View {
    let center: PageWatchCenter
    let coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(center.watches) { watch in
                    WatchRow(
                        watch: watch,
                        onOpen: { _ = coordinator.openNewTab(url: watch.url) },
                        onCheck: { Task { await center.check(watch.id) } },
                        onStop: { center.stop(watch.id) }
                    )
                    if watch.id != center.watches.last?.id {
                        Divider().overlay(Theme.Wash.hairline)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
    }
}

private struct WatchRow: View {
    let watch: PageWatch
    let onOpen: () -> Void
    let onCheck: () -> Void
    let onStop: () -> Void

    @State private var hovering = false

    private var interval: String {
        Duration.seconds(watch.interval).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: watch.title.isEmpty ? watch.place : watch.title)
                        .font(Theme.Font.rowTitle)
                        .lineLimit(1)
                    Text(verbatim: watch.place)
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Group {
                        if watch.condition.isEmpty {
                            Text("Waiting for any change")
                        } else {
                            Text("Waiting for \(watch.condition)")
                        }
                    }
                    .font(Theme.Font.body)
                    .padding(.top, 3)
                    if let state = watch.state, !state.isEmpty {
                        Text(verbatim: state)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        if let checked = watch.lastChecked {
                            Text("Every \(interval) · Checked \(checked.formatted(.relative(presentation: .named)))")
                        } else {
                            Text("Every \(interval)")
                        }
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.metaInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Open Page"))

            QuietIconButton(symbol: "xmark", isOn: false, help: String(localized: "Stop Watching"), action: onStop)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel(Text("Stop Watching"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open Page", action: onOpen)
            Button("Check Now", action: onCheck)
            Divider()
            Button("Stop Watching", action: onStop)
        }
    }
}
