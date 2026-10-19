// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GitHubPRIssues: View {
    let issues: [GitHubPRDetails.Issue]
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(issues) { issue in
                GitHubLinkRow(url: issue.url, onOpenURL: onOpenURL) {
                    Image(systemName: "smallcircle.filled.circle").foregroundStyle(Theme.success).frame(width: 14)
                    Text("Closes #\(issue.number)").foregroundStyle(.secondary).fixedSize()
                    Text(verbatim: issue.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(Theme.Font.body)
    }
}

private struct GitHubSectionTitle: View {
    let title: LocalizedStringResource
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let detail {
                Text(verbatim: detail).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.metaInk)
            }
        }
    }
}

struct GitHubPRSummary: View {
    let text: String
    let onOpenURL: (URL) -> Void
    @State private var expanded = false

    private var isLong: Bool {
        text.count > 600 || text.filter(\.isNewline).count > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GitHubSectionTitle(title: "Description")
            ChatMarkdown(text: text, fontSize: 12, spacing: 7, isDocument: true, onOpenLink: onOpenURL)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: isLong && !expanded ? 180 : nil, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .black.opacity(isLong && !expanded ? 0 : 1), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            if isLong {
                Button { expanded.toggle() } label: {
                    if expanded {
                        Text("Show Less")
                    } else {
                        Text("Show More")
                    }
                }
                .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
            }
        }
    }
}

struct GitHubPRFiles: View {
    let pr: GitHubInboxPR
    let details: GitHubPRDetails
    let onOpenURL: (URL) -> Void

    var body: some View {
        let top = details.files.sorted { $0.churn > $1.churn }.prefix(8)
        let widest = max(1, top.first?.churn ?? 1)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                GitHubSectionTitle(title: "Files", detail: "\(details.fileCount)")
                GitHubChurn(additions: pr.additions, deletions: pr.deletions)
            }
            .padding(.bottom, 4)
            ForEach(top) { file in
                GitHubLinkRow(url: fileURL(file), onOpenURL: onOpenURL) {
                    GitHubChurnBar(additions: file.additions, deletions: file.deletions, widest: widest)
                        .padding(.top, 4)
                    Text(verbatim: file.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    GitHubChurn(additions: file.additions, deletions: file.deletions)
                }
                .help(file.path)
            }
            if details.fileCount > top.count, let url = pr.reference?.url(for: .files) {
                Button("Show all \(details.fileCount) files") { onOpenURL(url) }
                    .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent).padding(.top, 4)
            }
        }
        .font(Theme.Font.body)
    }

    private func fileURL(_ file: GitHubPRDetails.File) -> URL? {
        guard let base = pr.reference?.url(for: .files),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = file.anchor
        return components.url
    }
}

struct GitHubChurn: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 4) {
            if additions > 0 {
                Text(verbatim: "+\(additions)").foregroundStyle(Theme.success)
            }
            if deletions > 0 {
                Text(verbatim: "−\(deletions)").foregroundStyle(Theme.danger)
            }
        }
        .font(Theme.Font.caption).monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

private struct GitHubChurnBar: View {
    let additions: Int
    let deletions: Int
    let widest: Int

    var body: some View {
        let total: CGFloat = 36
        let width = max(3, total * CGFloat(additions + deletions) / CGFloat(widest))
        let added = width * CGFloat(additions) / CGFloat(max(1, additions + deletions))
        HStack(spacing: 0) {
            Rectangle().fill(Theme.success).frame(width: added)
            Rectangle().fill(Theme.danger).frame(width: width - added)
        }
        .frame(width: width, height: 5)
        .clipShape(Capsule())
        .frame(width: total, alignment: .leading)
        .accessibilityHidden(true)
    }
}

struct GitHubPRActions: View {
    let reference: GitHubPullRequestReference
    let onOpen: (GitHubPullRequestReference, GitHubPullRequestSection) -> Void
    let onAsk: (GitHubPullRequestReference) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                open
                sections
                ask
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    open
                    changes
                    ask
                }
                HStack(spacing: 6) {
                    commits
                    checks
                }
            }
        }
    }

    private var open: some View {
        ToolbarChip(symbol: "arrow.up.right", label: "Open") { onOpen(reference, .conversation) }
    }

    @ViewBuilder
    private var sections: some View {
        changes
        commits
        checks
    }

    private var changes: some View {
        ToolbarChip(symbol: GitHubPullRequestSection.files.symbol, label: GitHubPullRequestSection.files.title) {
            onOpen(reference, .files)
        }
    }

    private var commits: some View {
        ToolbarChip(symbol: GitHubPullRequestSection.commits.symbol, label: GitHubPullRequestSection.commits.title) {
            onOpen(reference, .commits)
        }
    }

    private var checks: some View {
        ToolbarChip(symbol: GitHubPullRequestSection.checks.symbol, label: GitHubPullRequestSection.checks.title) {
            onOpen(reference, .checks)
        }
    }

    private var ask: some View {
        ToolbarChip(icon: .assistant, label: "Ask") { onAsk(reference) }
            .help(Text("Ask Assistant"))
    }
}
