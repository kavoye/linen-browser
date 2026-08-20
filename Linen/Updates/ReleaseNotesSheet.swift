// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ReleaseNotesSheet: View {
    let release: GitHubRelease
    let onClose: () -> Void

    private var subtitle: String {
        guard let published = release.publishedAt else { return "Linen \(UpdateFeed.currentVersion)" }
        return "Linen \(UpdateFeed.currentVersion) · \(published.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(release.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(Theme.Font.label)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                IconButton(symbol: "xmark", help: "Close", action: onClose)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            RowSeparator()

            ScrollView {
                MarkdownText(source: release.body ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .frame(maxHeight: 380)

            RowSeparator()

            HStack(spacing: 8) {
                SettingsButton(title: "View on GitHub") {
                    NSWorkspace.shared.open(release.htmlURL)
                }
                Spacer(minLength: 0)
                SettingsButton(title: "Done", isProminent: true, action: onClose)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480)
        .background(Theme.windowBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Wash.hover, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 40, y: 14)
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
