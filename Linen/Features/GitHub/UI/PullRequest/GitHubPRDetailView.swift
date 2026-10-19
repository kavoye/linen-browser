// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GitHubPRDetail: View {
    let pr: GitHubInboxPR
    let details: GitHubPRDetails?
    let isLoading: Bool
    let error: String?
    let showsBack: Bool
    let onBack: () -> Void
    let onOpen: (GitHubPullRequestReference, GitHubPullRequestSection) -> Void
    let onOpenURL: (URL) -> Void
    let onAsk: (GitHubPullRequestReference) -> Void
    let onRetry: () -> Void
    var onShowTeams: (() -> Void)?

    var body: some View {
        let digest = GitHubPRDigest(pr: pr, details: details)
        VStack(alignment: .leading, spacing: 16) {
            if showsBack {
                GitHubBackButton(action: onBack)
            }
            GitHubPRHeading(pr: pr, digest: digest)
            GitHubPRChecklist(pr: pr, details: details, digest: digest, isLoading: isLoading, error: error,
                              onOpenURL: onOpenURL, onRetry: onRetry, onShowTeams: onShowTeams)
            if let details {
                if !details.issues.isEmpty {
                    GitHubPRIssues(issues: details.issues, onOpenURL: onOpenURL)
                }
                if !details.summary.isEmpty {
                    GitHubPRSummary(text: details.summary, onOpenURL: onOpenURL)
                }
                if !details.files.isEmpty {
                    GitHubPRFiles(pr: pr, details: details, onOpenURL: onOpenURL)
                }
            }
            if let reference = pr.reference {
                GitHubPRActions(reference: reference, onOpen: onOpen, onAsk: onAsk)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension GitHubPRStatus.Tone {
    var color: Color {
        switch self {
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

private struct GitHubCopyLinkButton: View {
    let url: URL

    @State private var copiedAt: Date?

    var body: some View {
        ChromeIcon(
            symbol: copiedAt == nil ? "link" : "checkmark",
            size: 10.5,
            weight: .semibold,
            isSubdued: true,
            extent: 20,
            help: String(localized: "Copy Link")
        ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            copiedAt = .now
        }
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                copiedAt = nil
            } catch {}
        }
    }
}

private struct GitHubBackButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .hoverLift(hovering)
                Text("All pull requests")
            }
            .font(Theme.Font.control)
            .foregroundStyle(hovering ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct GitHubPRHeading: View {
    let pr: GitHubInboxPR
    let digest: GitHubPRDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(verbatim: "\(pr.repository.nameWithOwner) #\(pr.number)").lineLimit(1).truncationMode(.middle)
                if let author = pr.author {
                    Text(verbatim: "·")
                    GitHubAvatar(url: author.avatarURL, login: author.login, size: 14)
                    Text(verbatim: author.login).lineLimit(1)
                }
                Spacer(minLength: 4)
                GitHubCopyLinkButton(url: pr.reference?.url ?? pr.url)
            }
            .font(Theme.Font.secondary).foregroundStyle(.secondary)
            Text(verbatim: pr.title).font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !pr.labelList.isEmpty {
                WrapRow(spacing: 4, lineSpacing: 4, alignment: .leading) {
                    ForEach(pr.labelList, id: \.self) { GitHubLabelChip(label: $0) }
                }
            }
            GitHubBranchLine(pr: pr, copiesNames: true)
            HStack(spacing: 8) {
                GitHubStateBadge(pr: pr)
                if pr.state == "OPEN", let verdict = digest.verdict {
                    Text(verdict).font(Theme.Font.title)
                        .foregroundStyle(digest.tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(digest.tone.color))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
