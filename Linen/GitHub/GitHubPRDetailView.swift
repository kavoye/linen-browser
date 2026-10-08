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
                GitHubPRActions(pr: pr, reference: reference, onOpen: onOpen, onAsk: onAsk)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension GitHubPRStatus.Tone {
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

private struct GitHubPRChecklist: View {
    let pr: GitHubInboxPR
    let details: GitHubPRDetails?
    let digest: GitHubPRDigest
    let isLoading: Bool
    let error: String?
    let onOpenURL: (URL) -> Void
    let onRetry: () -> Void
    let onShowTeams: (() -> Void)?
    @State private var expanded: Set<GitHubPRDigest.Kind>?

    private var open: Set<GitHubPRDigest.Kind> {
        expanded ?? Set(digest.rows.filter { $0.expandable && $0.tone == .danger }.map(\.kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if details == nil {
                if let error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                        Text(verbatim: error).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 4)
                        Button("Try Again", action: onRetry).buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
                    .font(Theme.Font.body).padding(.horizontal, 12).padding(.vertical, 10)
                } else if isLoading {
                    HStack(spacing: 8) {
                        Spinner(size: 11).foregroundStyle(.secondary)
                        Text("Loading details…").foregroundStyle(.secondary)
                    }
                    .font(Theme.Font.body).padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
            ForEach(digest.rows) { row in
                let isOpen = row.expandable && open.contains(row.kind)
                GitHubChecklistRow(row: row, isOpen: isOpen) {
                    var next = open
                    if isOpen {
                        next.remove(row.kind)
                    } else {
                        next.insert(row.kind)
                    }
                    expanded = next
                }
                if isOpen, let details {
                    GitHubChecklistDetail(kind: row.kind, details: details, authorLogin: pr.author?.login,
                                          onOpenURL: onOpenURL, onShowTeams: onShowTeams)
                        .padding(.leading, 34).padding(.trailing, 12).padding(.bottom, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

private struct GitHubChecklistRow: View {
    let row: GitHubPRDigest.Row
    let isOpen: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        if row.expandable {
            Button(action: onToggle) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .animation(Theme.Motion.quick, value: isOpen)
                .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: row.detail == nil ? .center : .top, spacing: 8) {
            Image(systemName: row.symbol).foregroundStyle(row.tone.color).frame(width: 16)
                .padding(.top, row.detail == nil ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).foregroundStyle(.primary)
                    .fontWeight(row.detail == nil ? .regular : .semibold)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let detail = row.detail {
                    Text(verbatim: detail).font(Theme.Font.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if row.expandable {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.metaInk)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .font(Theme.Font.body)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovering && row.expandable ? Theme.Wash.hover : .clear)
        .contentShape(Rectangle())
    }
}

private struct GitHubChecklistDetail: View {
    let kind: GitHubPRDigest.Kind
    let details: GitHubPRDetails
    let authorLogin: String?
    let onOpenURL: (URL) -> Void
    let onShowTeams: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch kind {
            case .checks:
                ForEach(details.checks) { check in
                    GitHubCheckRow(check: check, onOpenURL: onOpenURL)
                }
            case .review:
                ForEach(details.reviews, id: \.author.login) { review in
                    HStack(spacing: 6) {
                        GitHubAvatar(url: review.author.avatarURL, login: review.author.login, size: 16)
                        Text(verbatim: review.author.login).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.reviewLabel(review.state))
                            .foregroundStyle(review.state == "APPROVED" ? Theme.success : review.state == "CHANGES_REQUESTED" ? Theme.danger : .secondary)
                    }
                    .padding(.vertical, 3)
                }
                ForEach(details.pendingReviewers, id: \.login) { reviewer in
                    HStack(spacing: 6) {
                        GitHubAvatar(url: reviewer.avatarURL, login: reviewer.login, size: 16)
                        Text(verbatim: reviewer.login).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Pending").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                if details.hiddenTeams > 0 {
                    HStack(spacing: 6) {
                        Text("\(details.hiddenTeams) teams").foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if let onShowTeams {
                            Button("Show Team Names…", action: onShowTeams)
                                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                                .help("Reconnect GitHub to show team names.")
                        } else {
                            Text("Pending").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            case .threads:
                GitHubCommentList(comments: details.threads, authorLogin: authorLogin, limit: 20, onOpenURL: onOpenURL)
            case .comments:
                GitHubCommentList(comments: details.comments, authorLogin: authorLogin, limit: 5, onOpenURL: onOpenURL)
            case .conflicts, .base:
                EmptyView()
            }
        }
        .font(Theme.Font.secondary)
    }

    private static func reviewLabel(_ state: String) -> LocalizedStringResource {
        switch state {
        case "APPROVED":
            "Approved"
        case "CHANGES_REQUESTED":
            "Changes requested"
        case "DISMISSED":
            "Dismissed"
        default:
            "Commented"
        }
    }
}

private struct GitHubCommentList: View {
    let comments: [GitHubPRDetails.Comment]
    let authorLogin: String?
    let limit: Int
    let onOpenURL: (URL) -> Void
    @State private var showsBots = false

    var body: some View {
        let people = comments.filter { !$0.isBot }
        let bots = comments.filter(\.isBot)
        ForEach(people.prefix(limit)) { comment in
            GitHubCommentRow(comment: comment, authorLogin: authorLogin, onOpenURL: onOpenURL)
        }
        if people.count > limit {
            Text("\(people.count - limit) older").foregroundStyle(Theme.metaInk).padding(.vertical, 3)
        }
        if !bots.isEmpty {
            Button {
                showsBots.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").frame(width: 12)
                    Text("\(bots.count) from bots")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(showsBots ? 90 : 0))
                }
                .foregroundStyle(.secondary).padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsBots {
                ForEach(bots) { comment in
                    GitHubCommentRow(comment: comment, authorLogin: authorLogin, onOpenURL: onOpenURL)
                }
            }
        }
    }
}

private struct GitHubCheckRow: View {
    let check: GitHubPRDetails.Check
    let onOpenURL: (URL) -> Void

    private var state: (symbol: String, color: Color) {
        switch check.state {
        case .failed:
            ("xmark", Theme.danger)
        case .pending:
            ("clock", Theme.warning)
        case .passed:
            ("checkmark", Theme.success)
        case .skipped:
            ("slash.circle", .secondary)
        }
    }

    var body: some View {
        GitHubLinkRow(url: check.url, onOpenURL: onOpenURL) {
            Image(systemName: state.symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(state.color).frame(width: 12).padding(.top, 2)
            Group {
                if let icon = check.iconURL {
                    GitHubCachedImage(url: icon) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3)).padding(.top, 1)
            .accessibilityHidden(true)
            Text(verbatim: check.title).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(check.state == .skipped ? .secondary : .primary)
            Spacer(minLength: 4)
            if check.state == .pending {
                Text("In progress").foregroundStyle(Theme.metaInk).lineLimit(1)
            } else if let duration = check.duration {
                Text(verbatim: Duration.seconds(duration.rounded())
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                    .foregroundStyle(Theme.metaInk).monospacedDigit().lineLimit(1)
                    .help(check.date.map { $0.formatted(date: .complete, time: .shortened) } ?? "")
            } else if let date = check.date {
                GitHubRelativeDate(date: date)
            }
        }
        .help(check.title)
    }
}

private struct GitHubRelativeDate: View {
    let date: Date

    var body: some View {
        Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            .foregroundStyle(Theme.metaInk).lineLimit(1)
            .help(date.formatted(date: .complete, time: .shortened))
    }
}

private struct GitHubCommentRow: View {
    let comment: GitHubPRDetails.Comment
    let authorLogin: String?
    let onOpenURL: (URL) -> Void
    @State private var expanded = false
    @State private var hovering = false

    private var snippet: String {
        comment.text.prefix(400).split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Button { expanded.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            GitHubAvatar(url: comment.author?.avatarURL, login: comment.author?.login ?? "", size: 16)
                            Text(verbatim: comment.author?.login ?? "ghost").fontWeight(.medium).lineLimit(1)
                            if let login = comment.author?.login, login.caseInsensitiveCompare(authorLogin ?? "") == .orderedSame {
                                Text("Author")
                                    .font(Theme.Font.micro).foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .overlay(Capsule().strokeBorder(Theme.Wash.strong))
                                    .fixedSize()
                            }
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.metaInk)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .animation(Theme.Motion.quick, value: expanded)
                            if let path = comment.path {
                                Text(verbatim: comment.line.map { "\(path):\($0)" } ?? path)
                                    .font(Theme.Font.monoCaption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                            Spacer(minLength: 4)
                            if let date = comment.date {
                                GitHubRelativeDate(date: date)
                            }
                        }
                        if !expanded {
                            Text(verbatim: snippet).foregroundStyle(.secondary).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                if let url = comment.url {
                    ChromeIcon(symbol: "arrow.up.right", size: 9, weight: .semibold, extent: 16,
                               help: String(localized: "Open Comment on GitHub")) { onOpenURL(url) }
                }
            }
            if expanded {
                ChatMarkdown(text: GitHubPRDetails.readable(comment.markdown), fontSize: 11.5, spacing: 6, isDocument: true, onOpenLink: onOpenURL)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(hovering || expanded ? Theme.Wash.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
    }
}

private struct GitHubLinkRow<Content: View>: View {
    let url: URL?
    let onOpenURL: (URL) -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button {
            url.map(onOpenURL)
        } label: {
            HStack(alignment: .top, spacing: 6) { content }
                .padding(.vertical, 4).padding(.horizontal, 6)
                .background(hovering && url != nil ? Theme.Wash.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .disabled(url == nil)
        .onHover { hovering = $0 }
    }
}

private struct GitHubPRIssues: View {
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

private struct GitHubPRSummary: View {
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

private struct GitHubPRFiles: View {
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

private struct GitHubPRActions: View {
    let pr: GitHubInboxPR
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
