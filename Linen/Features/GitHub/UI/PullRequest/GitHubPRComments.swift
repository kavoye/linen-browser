// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct GitHubCommentList: View {
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

struct GitHubRelativeDate: View {
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
        .hoverSheet(isActive: hovering || expanded, in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
    }
}

struct GitHubLinkRow<Content: View>: View {
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
                .hoverSheet(isActive: hovering && url != nil, in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .disabled(url == nil)
        .onHover { hovering = $0 }
    }
}
