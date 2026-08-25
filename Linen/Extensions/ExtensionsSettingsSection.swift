// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ExtensionsSettingsCard: View {
    let coordinator: AppCoordinator

    private var manager: ExtensionManager {
        coordinator.extensions
    }

    var body: some View {
        Group {
            if manager.installed.isEmpty {
                Text("No extensions installed yet.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, SettingsMetrics.rowPaddingH)
                    .padding(.vertical, SettingsMetrics.rowPaddingV)
            }

            ForEach(manager.installed.enumerated(), id: \.element.id) { index, record in
                if index > 0 {
                    RowSeparator()
                }
                ExtensionRow(manager: manager, record: record)
            }
        }
    }
}

struct SafariExtensionsSettingsCard: View {
    let coordinator: AppCoordinator

    private var manager: ExtensionManager {
        coordinator.extensions
    }

    var body: some View {
        Group {
            if !manager.systemExtensions.isEmpty {
                SettingsSection(
                    title: "Safari extensions",
                    symbol: "safari",
                    footnote: "Turn on any Safari extension you already have. The App Store keeps it up to date."
                ) {
                    ForEach(manager.systemExtensions.enumerated(), id: \.element.id) { index, record in
                        if index > 0 {
                            RowSeparator()
                        }
                        ExtensionRow(manager: manager, record: record)
                    }
                }
            }
        }
        .task { await manager.discoverSystemExtensions() }
    }
}

private struct ExtensionRowMenu: View {
    let manager: ExtensionManager
    let record: InstalledExtension

    @State private var hovering = false

    var body: some View {
        Menu {
            if manager.hasOptionsPage(id: record.id) {
                Button("Extension Options") {
                    manager.openOptionsPage(id: record.id)
                }

                Divider()
            }

            Button("Remove Extension", role: .destructive) {
                manager.confirmUninstall(id: record.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: SettingsMetrics.controlHeight,
                    height: SettingsMetrics.controlHeight
                )
                .settingsSurface(isActive: hovering, isLifted: true, in: Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("More Options"))
    }
}

private struct ExtensionRow: View {
    let manager: ExtensionManager
    let record: InstalledExtension

    @State private var icon: NSImage?
    @State private var showingIssues = false
    @Environment(\.settingsIsCompact) private var isCompact
    @State private var hovering = false

    private var errorCount: Int {
        manager.errorCount(for: record.id)
    }

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    name
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        controls
                    }
                }
            } else {
                HStack(spacing: 12) {
                    name
                    controls
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .task(id: record.id) {
            icon = await manager.icon(for: record.id)
        }
    }

    @ViewBuilder
    private var name: some View {
        HStack(spacing: 12) {
            ExtensionIcon(image: icon)
                .opacity(record.enabled ? 1 : 0.55)

            HStack(spacing: 6) {
                Text(verbatim: record.displayName)
                    .font(Theme.Font.title)
                    .lineLimit(isCompact ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)

                if record.enabled, errorCount > 0 {
                    Button {
                        showingIssues = true
                    } label: {
                        Tag("\(errorCount) issues")
                            .foregroundStyle(Theme.warning)
                    }
                    .buttonStyle(.plain)
                    .help("Show what went wrong")
                    .popover(isPresented: $showingIssues, arrowEdge: .bottom) {
                        IssueList(name: record.displayName, issues: manager.errors(for: record.id))
                    }
                }

                if hovering, !record.version.isEmpty {
                    Text(verbatim: record.version)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if !record.isSystem {
            ExtensionRowMenu(manager: manager, record: record)
        }

        SettingsToggle(Binding(
            get: { record.enabled },
            set: { manager.setEnabled($0, id: record.id) }
        ))
    }
}

private struct IssueList: View {
    let name: String
    let issues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: name)
                .font(.system(size: 12, weight: .semibold))

            if issues.isEmpty {
                Text("The issue has cleared — turn the extension off and on to refresh the badge.")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(issues.enumerated(), id: \.offset) { _, issue in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.warning)
                            .padding(.top, 2)
                        Text(verbatim: issue)
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Text("Usually a part of the extension WebKit doesn’t support. The rest keeps working.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 320, alignment: .leading)
        .padding(14)
    }
}

private struct ExtensionIcon: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .background(Theme.Wash.hairline, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}
