// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Observation
import SwiftUI

@MainActor
@Observable
final class GitHubPreviewPresenter {
    struct Shown: Equatable {
        let rowID: String
        let item: GitHubInboxItem
        var anchor: CGRect
    }

    private(set) var shown: Shown?
    @ObservationIgnored private var anchors: [String: CGRect] = [:]

    func show(_ item: GitHubInboxItem, rowID: String) {
        guard let anchor = anchors[rowID] else { return }
        shown = Shown(rowID: rowID, item: item, anchor: anchor)
    }

    func moved(_ rowID: String, anchor: CGRect) {
        anchors[rowID] = anchor
        guard shown?.rowID == rowID else { return }
        shown?.anchor = anchor
    }

    func hide(_ rowID: String) {
        guard shown?.rowID == rowID else { return }
        shown = nil
    }

    func removed(_ rowID: String) {
        anchors[rowID] = nil
        hide(rowID)
    }

    func dismiss() {
        shown = nil
    }
}

struct GitHubPreviewOverlay: View {
    let presenter: GitHubPreviewPresenter
    let model: GitHubPanelModel

    @State private var cardSize: CGSize = .zero

    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            if let shown = presenter.shown {
                let origin = proxy.frame(in: .global).origin
                let x = max(shown.anchor.minX - origin.x - cardSize.width - Self.gap, Self.margin)
                let y = min(
                    max(shown.anchor.midY - origin.y - cardSize.height / 2, Self.margin),
                    max(proxy.size.height - cardSize.height - Self.margin, Self.margin)
                )
                Group {
                    if let pr = shown.item.pr {
                        GitHubPRPreview(pr: pr, details: model.details[pr.id], thread: model.thread(for: shown.item))
                    } else {
                        GitHubThreadCard(item: shown.item, load: model.thread(for: shown.item) ?? .failed)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                .offset(x: x, y: y)
                .opacity(cardSize == .zero ? 0 : 1)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(Theme.Motion.quick, value: presenter.shown?.rowID)
    }
}

struct GitHubThreadCard: View {
    let item: GitHubInboxItem
    let load: GitHubThreadLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(verbatim: item.number.map { "\(item.repository) #\($0)" } ?? item.repository)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(item.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            }
            .font(Theme.Font.caption).foregroundStyle(.secondary)
            Text(verbatim: item.title).font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            GitHubLatestPost(load: load)
            if case .loaded(let thread) = load, thread.commentCount > 0 {
                Divider()
                Label {
                    Text("\(thread.commentCount) comments")
                } icon: {
                    Image(systemName: "bubble.left")
                }
                .font(Theme.Font.caption).foregroundStyle(Theme.metaInk)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

struct GitHubLatestPost: View {
    let load: GitHubThreadLoad

    var body: some View {
        switch load {
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                GitHubSkeletonBar(width: 120, height: 8)
                GitHubSkeletonBar(height: 8)
                GitHubSkeletonBar(height: 8)
            }
            .skeletonPulse()
            .accessibilityHidden(true)
        case .failed:
            Text("Couldn’t load the latest comment.")
                .font(Theme.Font.secondary).foregroundStyle(.secondary)
        case .loaded(let thread):
            let post = thread.latest ?? thread.opening
            let login = post.author?.login ?? "ghost"
            let text = post.body.split(whereSeparator: \.isNewline)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    GitHubAvatar(url: post.author?.avatarURL, login: login, size: 14)
                    Group {
                        if thread.latest == nil {
                            Text("\(Text(verbatim: login).fontWeight(.medium).foregroundStyle(.primary)) opened")
                        } else {
                            Text("\(Text(verbatim: login).fontWeight(.medium).foregroundStyle(.primary)) commented")
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(post.createdAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .foregroundStyle(Theme.metaInk)
                }
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                if text.isEmpty {
                    Text("No description provided.")
                        .font(Theme.Font.secondary).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: text)
                        .font(Theme.Font.secondary)
                        .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
