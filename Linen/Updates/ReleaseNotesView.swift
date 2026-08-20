// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ReleaseNotesView: View {
    let browser: BrowserModel
    let notes: ReleaseNotesModel

    var body: some View {
        DestinationPage {
            toolbar
        } content: {
            content
        }
        .task { await notes.load() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            DestinationTitle(title: "Release Notes") {
                browser.dismissInternalPage(.releaseNotes)
            }

            if !notes.releases.isEmpty {
                DestinationCount(count: notes.releases.count)
            }

            Spacer(minLength: 12)

            ToolbarChip(symbol: "arrow.up.forward", label: "View on GitHub") {
                NSWorkspace.shared.open(UpdateFeed.releasesURL)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if notes.releases.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                emptyLine
                    .font(Theme.Font.row)
                    .foregroundStyle(.tertiary)

                if !notes.isLoading {
                    SettingsButton(title: "Try Again") {
                        Task { await notes.reload() }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 28)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(notes.releases.enumerated()), id: \.element.id) { index, release in
                    if index > 0 {
                        RowSeparator()
                            .padding(.vertical, 20)
                    }
                    ReleaseNotesSection(release: release, isRunning: notes.isRunning(release))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private var emptyLine: some View {
        if notes.isLoading {
            Text("Looking for the notes…")
        } else {
            Text("No notes are published yet.")
        }
    }
}

private struct ReleaseNotesSection: View {
    let release: GitHubRelease
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(verbatim: release.displayTitle)
                        .font(.system(size: 15, weight: .semibold))

                    if isRunning {
                        Text(verbatim: String(
                            localized: "releaseNotes.installedBadge",
                            defaultValue: "Installed",
                            comment: """
                                Badge beside the version you are running, in the list of every \
                                release on the Release Notes page. Shares its English text with \
                                the Chrome Web Store marker of the same name, which is why it \
                                carries a key of its own.
                                """
                        ))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                }

                if let published = release.publishedAt {
                    Text(verbatim: published.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Font.label)
                        .foregroundStyle(.tertiary)
                }
            }

            MarkdownText(source: release.body ?? "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownText: View {
    let source: String

    private enum Kind {
        case heading(String, level: Int)
        case bullet(String)
        case paragraph(String)
        case rule
    }

    private struct Block: Identifiable {
        let id: Int
        let kind: Kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text("No notes for this release.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.tertiary)
            }
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let text, let level):
                    inline(text)
                        .font(.system(size: level <= 2 ? 13 : 12, weight: .semibold))
                        .padding(.top, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(Theme.Font.body)
                            .foregroundStyle(.tertiary)
                        inline(text)
                            .font(Theme.Font.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let text):
                    inline(text)
                        .font(Theme.Font.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                case .rule:
                    RowSeparator().padding(.vertical, 2)
                }
            }
        }
    }

    private func inline(_ text: String) -> Text {
        let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return Text(parsed ?? AttributedString(text))
    }

    private var blocks: [Block] {
        var kinds: [Kind] = []
        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }

            if line == "---" || line == "***" || line == "___" {
                kinds.append(.rule)
            } else if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                kinds.append(.heading(text, level: level))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                kinds.append(.bullet(String(line.dropFirst(2))))
            } else {
                kinds.append(.paragraph(line))
            }
        }
        return kinds.enumerated().map { Block(id: $0.offset, kind: $0.element) }
    }
}
