// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GitHubPRChecklist: View {
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
