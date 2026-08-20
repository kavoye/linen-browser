// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ExtensionsSettingsCard: View {
    let coordinator: AppCoordinator

    private var manager: ExtensionManager {
        coordinator.extensions
    }

    var body: some View {
        SettingsCard {
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

private struct ExtensionRow: View {
    let manager: ExtensionManager
    let record: InstalledExtension

    @State private var icon: NSImage?
    @State private var showingIssues = false

    private var errorCount: Int {
        manager.errorCount(for: record.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            ExtensionIcon(image: icon)

            HStack(spacing: 6) {
                Text(verbatim: record.displayName)
                    .font(Theme.Font.title)
                    .lineLimit(1)

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

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsButton(title: "Remove…", isDestructive: true) {
                manager.confirmUninstall(id: record.id)
            }

            SettingsToggle(Binding(
                get: { record.enabled },
                set: { manager.setEnabled($0, id: record.id) }
            ))
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
        .opacity(record.enabled ? 1 : 0.6)
        .task(id: record.id) {
            icon = await manager.icon(for: record.id)
        }
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
        .background(Theme.Wash.hairline, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
