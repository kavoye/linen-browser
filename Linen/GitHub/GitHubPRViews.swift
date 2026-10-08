// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GitHubStateBadge: View {
    let pr: GitHubInboxPR

    private var style: (title: LocalizedStringResource, symbol: String, color: Color) {
        if pr.state == "MERGED" {
            return ("Merged", "arrow.triangle.merge", Color(nsColor: .systemPurple))
        }
        if pr.state == "CLOSED" {
            return ("Closed", "arrow.triangle.pull", Theme.danger)
        }
        if pr.isDraft {
            return ("Draft", "arrow.triangle.pull", Color(nsColor: .systemGray))
        }
        return ("Open", "arrow.triangle.pull", Theme.success)
    }

    var body: some View {
        Label { Text(style.title) } icon: { Image(systemName: style.symbol) }
            .font(Theme.Font.control)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).frame(height: 24)
            .background(style.color, in: Capsule())
            .fixedSize()
    }
}

struct GitHubBranchPill: View {
    let name: String
    var copies: String?

    @State private var hovering = false
    @State private var copiedAt: Date?

    var body: some View {
        if let copies {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copies, forType: .string)
                copiedAt = .now
            } label: {
                HStack(spacing: 4) {
                    label
                    if hovering || copiedAt != nil {
                        Image(systemName: copiedAt == nil ? "doc.on.doc" : "checkmark")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(hovering ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tight))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Theme.Motion.quick, value: hovering)
            .animation(Theme.Motion.quick, value: copiedAt)
            .help(Text("Copy Branch Name"))
            .task(id: copiedAt) {
                guard copiedAt != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(1.2))
                    copiedAt = nil
                } catch {}
            }
        } else {
            label
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                .textSelection(.enabled)
                .help(name)
        }
    }

    private var label: some View {
        Text(verbatim: name)
            .font(Theme.Font.monoCaption)
            .foregroundStyle(Theme.accent)
            .lineLimit(1).truncationMode(.middle)
    }
}

struct GitHubLabelChip: View {
    let label: GitHubInboxPR.Label
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = label.rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .gray
        let ink = label.ink(dark: colorScheme == .dark)
        let text = Color(red: ink.red, green: ink.green, blue: ink.blue)
        Text(verbatim: label.name)
            .font(Theme.Font.micro.weight(.medium))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(base.opacity(colorScheme == .dark ? 0.22 : 0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(text.opacity(0.45)))
            .fixedSize()
    }
}

struct GitHubPRPreview: View {
    let pr: GitHubInboxPR
    let details: GitHubPRDetails?
    var thread: GitHubThreadLoad?
    var padded = true

    var body: some View {
        let digest = GitHubPRDigest(pr: pr, details: details)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(verbatim: "\(pr.repository.nameWithOwner) #\(pr.number)").lineLimit(1).truncationMode(.middle)
                if let author = pr.author {
                    Text(verbatim: "·")
                    GitHubAvatar(url: author.avatarURL, login: author.login, size: 14)
                    Text(verbatim: author.login).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(pr.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            }
            .font(Theme.Font.caption).foregroundStyle(.secondary)
            Text(verbatim: pr.title).font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            GitHubBranchLine(pr: pr)
            if !pr.labelList.isEmpty {
                WrapRow(spacing: 4, lineSpacing: 4, alignment: .leading) {
                    ForEach(pr.labelList, id: \.self) { GitHubLabelChip(label: $0) }
                }
            }
            GitHubPRStatusStrip(pr: pr, digest: digest)
            if let summary = details?.summary, !summary.isEmpty {
                Divider()
                Text(verbatim: Self.plain(summary))
                    .font(Theme.Font.secondary).foregroundStyle(.secondary)
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true)
            } else if details == nil {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    GitHubSkeletonBar(height: 8)
                    GitHubSkeletonBar(height: 8)
                    GitHubSkeletonBar(width: 140, height: 8)
                }
                .skeletonPulse()
                .accessibilityHidden(true)
            }
            if let thread {
                Divider()
                GitHubLatestPost(load: thread)
            }
        }
        .padding(padded ? 14 : 0)
        .frame(width: padded ? 320 : nil, alignment: .leading)
    }

    private static func plain(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "(?m)^#{1,6}\\s.*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^\\s*(?:[-*+]|\\d+\\.)\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
    }
}

struct GitHubPRStatusStrip: View {
    let pr: GitHubInboxPR
    let digest: GitHubPRDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GitHubStateBadge(pr: pr)
                if pr.state == "OPEN", let verdict = digest.verdict {
                    Text(verdict).font(Theme.Font.control)
                        .foregroundStyle(Self.color(digest.tone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                GitHubPRSignals(pr: pr)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("\(pr.changedFiles) files").foregroundStyle(.secondary).monospacedDigit()
                    GitHubChurn(additions: pr.additions, deletions: pr.deletions)
                }
            }
            .font(Theme.Font.caption)
        }
    }

    private static func color(_ tone: GitHubPRStatus.Tone) -> Color {
        switch tone {
        case .success:
            Theme.success
        case .danger:
            Theme.danger
        case .warning:
            Theme.warning
        case .neutral:
            .secondary
        }
    }
}

struct GitHubBranchLine: View {
    let pr: GitHubInboxPR
    var copiesNames = false

    var body: some View {
        HStack(spacing: 5) {
            GitHubBranchPill(name: pr.baseLabel, copies: copiesNames ? pr.baseRefName : nil).layoutPriority(1)
            Text("from").font(Theme.Font.caption).foregroundStyle(.secondary).fixedSize()
            GitHubBranchPill(name: pr.headLabel, copies: copiesNames ? pr.headRefName : nil)
        }
    }
}
