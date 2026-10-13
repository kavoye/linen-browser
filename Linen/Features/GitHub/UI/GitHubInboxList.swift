// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GitHubInboxList: View {
    let model: GitHubPanelModel
    let onOpen: (URL) -> Void
    @State private var collapsed: Set<GitHubInboxSection.Kind> = [.other]

    var body: some View {
        let sections = model.sections
        LazyVStack(alignment: .leading, spacing: 2) {
            if sections.isEmpty {
                emptyState
            }
            ForEach(sections) { section in
                let isCollapsed = collapsed.contains(section.kind)
                Section {
                    if !isCollapsed {
                        ForEach(section.items) { item in
                            GitHubInboxRow(
                                item: item, selected: model.selectedItemID == item.id,
                                markingRead: item.notification.map { model.markingRead.contains($0.id) } ?? false,
                                onSelect: { model.select(item, open: onOpen) },
                                onOpen: { item.url.map(onOpen) },
                                onRead: { item.notification.map(model.markRead) },
                                onPreview: item.pr != nil || item.showsThread ? { @MainActor in model.loadPreview(for: item) } : nil
                            )
                            .equatable()
                        }
                    }
                } header: {
                    GitHubInboxSectionHeader(section: section, collapsed: isCollapsed) {
                        if isCollapsed {
                            collapsed.remove(section.kind)
                        } else {
                            collapsed.insert(section.kind)
                        }
                    }
                }
            }
            if model.hasMoreNotifications {
                Button("Load more notifications") { model.loadMore(notifications: true) }
                    .buttonStyle(GitHubRowButtonStyle())
                    .disabled(model.isLoadingMore || model.isRefreshing)
                    .padding(.top, 8)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isRefreshing {
            GitHubListSkeleton(label: "Loading your inbox…")
        } else if model.errorMessage != nil {
            GitHubEmptyState(symbol: "exclamationmark.triangle", title: "Couldn’t load your inbox", detail: "Refresh to try again.")
        } else {
            GitHubEmptyState(symbol: "tray", title: "You’re all caught up",
                             detail: "Review requests, mentions, and your pull requests appear here.")
        }
    }
}

struct GitHubListSkeleton: View {
    private static let widths: [(CGFloat, CGFloat, CGFloat)] = [
        (0.35, 0.85, 0.5), (0.45, 0.7, 0.4), (0.3, 0.9, 0.55), (0.4, 0.6, 0.45), (0.35, 0.75, 0.35),
    ]
    let label: LocalizedStringResource
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsHeader {
                bar(width: 90, height: 8)
                    .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
            }
            ForEach(Self.widths.indices, id: \.self) { index in
                let widths = Self.widths[index]
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: Theme.Radius.tight).fill(Theme.Wash.hover)
                        .frame(width: 16, height: 16)
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 7) {
                            bar(width: proxy.size.width * widths.0, height: 8)
                            bar(width: proxy.size.width * widths.1, height: 11)
                            bar(width: proxy.size.width * widths.2, height: 8)
                        }
                    }
                    .frame(height: 42)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .skeletonPulse()
        .accessibilityElement()
        .accessibilityLabel(Text(label))
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GitHubSkeletonBar(width: width, height: height)
    }
}

struct GitHubSkeletonBar: View {
    var width: CGFloat?
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2).fill(Theme.Wash.hover)
            .frame(width: width, height: height)
    }
}

private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

extension View {
    func skeletonPulse() -> some View {
        modifier(SkeletonPulse())
    }
}

private struct GitHubInboxSectionHeader: View {
    let section: GitHubInboxSection
    let collapsed: Bool
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Text(section.title).font(Theme.Font.caption.weight(.semibold))
                Text(section.items.count, format: .number).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.metaInk)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.metaInk)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: collapsed)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(collapsed ? Text("Collapsed") : Text("Expanded"))
    }
}

struct GitHubInboxRow: View, Equatable {
    let item: GitHubInboxItem
    let selected: Bool
    let markingRead: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRead: () -> Void
    var onPreview: (@MainActor () -> Void)?
    @State private var hovering = false
    @State private var hoveringRead = false
    @Environment(GitHubPreviewPresenter.self) private var presenter: GitHubPreviewPresenter?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.selected == rhs.selected && lhs.markingRead == rhs.markingRead
            && (lhs.onPreview == nil) == (rhs.onPreview == nil)
    }

    private var tone: Color? {
        guard item.reason == .authored, let status = item.status else { return nil }
        return switch status.tone {
        case .danger:
            Theme.danger
        case .warning:
            Theme.warning
        case .success:
            Theme.success
        case .neutral:
            nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                presenter?.dismiss()
                onSelect()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(tone.map { AnyShapeStyle($0) } ?? (item.isUnread ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)))
                        .frame(width: 16).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if item.isUnread {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6).accessibilityLabel("Unread")
                            }
                            Group {
                                if item.reason == .opened, let author = item.pr?.author {
                                    Text("Opened by")
                                    GitHubAvatar(url: author.avatarURL, login: author.login, size: 12)
                                    Text(verbatim: author.login).lineLimit(1)
                                } else {
                                    Text(item.headline).lineLimit(1)
                                }
                            }
                            .foregroundStyle(tone.map { AnyShapeStyle($0) } ?? (item.isUnread ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
                            .fontWeight(item.isUnread ? .medium : .regular)
                            Spacer(minLength: 4)
                            if !(hovering && item.isUnread) {
                                Text(item.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                                    .foregroundStyle(Theme.metaInk).lineLimit(1)
                            }
                        }
                        .font(Theme.Font.caption)
                        Text(verbatim: item.title).font(Theme.Font.rowTitle)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(verbatim: item.number.map { "\(item.repository) #\($0)" } ?? item.repository)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            if item.reason != .authored, item.reason != .opened, let author = item.pr?.author {
                                HStack(spacing: 3) {
                                    Text(verbatim: "·")
                                    GitHubAvatar(url: author.avatarURL, login: author.login, size: 12)
                                    Text(verbatim: author.login).lineLimit(1)
                                }
                                .foregroundStyle(.secondary).layoutPriority(1)
                            }
                        }
                        .font(Theme.Font.caption)
                        if let pr = item.pr {
                            HStack(spacing: 8) {
                                GitHubPRSignals(pr: pr)
                                Spacer(minLength: 0)
                                GitHubChurn(additions: pr.additions, deletions: pr.deletions)
                                    .help(Text("\(pr.changedFiles) files"))
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            if hovering && item.isUnread {
                Button(action: onRead) {
                    Image(systemName: "checkmark").font(Theme.Font.caption).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(hoveringRead ? Theme.Wash.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(hoveringRead ? .primary : .secondary).disabled(markingRead)
                .onHover { hoveringRead = $0 }
                .onDisappear { hoveringRead = false }
                .help("Mark as Read").accessibilityLabel("Mark as Read")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(selected ? Theme.Wash.selection : hovering ? Theme.Wash.hover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
            presenter?.moved(item.id, anchor: rect)
        }
        .task(id: hovering && !hoveringRead) {
            guard hovering, !hoveringRead, !selected, let onPreview, let presenter else {
                presenter?.hide(item.id)
                return
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, hovering, !hoveringRead else { return }
            onPreview()
            presenter.show(item, rowID: item.id)
        }
        .onDisappear { presenter?.removed(item.id) }
        .contextMenu {
            if item.url != nil {
                Button("Open in New Tab", action: onOpen)
            }
            if item.isUnread {
                Button("Mark as Read", action: onRead).disabled(markingRead)
            }
        }
    }
}

struct GitHubPRSignals: View {
    let pr: GitHubInboxPR

    var body: some View {
        HStack(spacing: 7) {
            switch pr.checks {
            case "SUCCESS":
                checks("checkmark", Theme.success)
            case "FAILURE", "ERROR":
                checks("xmark", Theme.danger)
            case "PENDING", "EXPECTED":
                checks("circle.dotted", .secondary)
            default:
                EmptyView()
            }
            switch pr.reviewDecision {
            case "APPROVED":
                signal("person.crop.circle.badge.checkmark", Theme.success, help: pr.reviewLabel)
            case "CHANGES_REQUESTED":
                signal("person.crop.circle.badge.xmark", Theme.warning, help: pr.reviewLabel)
            case "REVIEW_REQUIRED":
                signal("minus.circle.fill", Theme.warning, help: "Review required")
            default:
                EmptyView()
            }
            if pr.mergeable == "CONFLICTING" {
                signal("exclamationmark.triangle.fill", Theme.warning, help: "Merge conflicts")
            }
            if pr.comments.totalCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                    Text(pr.comments.totalCount, format: .number).monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .help(Text("\(pr.comments.totalCount) comments"))
            }
        }
        .font(Theme.Font.caption)
        .fixedSize()
    }

    private func checks(_ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color)
            if let counts = pr.checkCounts {
                Text(verbatim: "\(counts.passed)/\(counts.total)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .help(Text(pr.checksLabel))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(pr.checksLabel))
    }

    private func signal(_ symbol: String, _ color: Color, help: LocalizedStringResource) -> some View {
        Image(systemName: symbol).foregroundStyle(color).help(Text(help)).accessibilityLabel(Text(help))
    }
}
