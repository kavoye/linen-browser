// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantAttachMenu: View {
    static let width: CGFloat = 280
    static let collapsedRows = 5

    private static let inset: CGFloat = 8
    private static let textInset: CGFloat = 6
    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 2
    private static let visibleRows = 8

    static var plateRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.systemPopover, inset: inset)
    }

    enum Item: Hashable {
        case tab(UUID)
        case viewMore
        case upload
    }

    let tabs: [BrowserTab]
    let activeTabID: UUID?
    let attachedTabIDs: Set<UUID>
    let onAttachTab: (BrowserTab) -> Void
    let onChooseFiles: () -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var isExpanded = false
    @State private var highlight: Item?

    private var matches: [BrowserTab] {
        AskSurfaceInteraction.mentionCandidates(
            fragment: query,
            tabs: tabs,
            mentionedTabIDs: attachedTabIDs,
            activeTabID: activeTabID,
            limit: .max
        )
    }

    private var listed: [BrowserTab] {
        Self.listed(matches, isSearching: !query.isEmpty, isExpanded: isExpanded)
    }

    private var items: [Item] {
        Self.items(listed: listed, matchCount: matches.count)
    }

    private var current: Item? {
        Self.current(highlight, in: items)
    }

    static func listed(_ matches: [BrowserTab], isSearching: Bool, isExpanded: Bool) -> [BrowserTab] {
        isSearching || isExpanded ? matches : Array(matches.prefix(collapsedRows))
    }

    static func items(listed: [BrowserTab], matchCount: Int) -> [Item] {
        listed.map { .tab($0.id) } + (listed.count < matchCount ? [.viewMore] : []) + [.upload]
    }

    static func current(_ highlight: Item?, in items: [Item]) -> Item? {
        if let highlight, items.contains(highlight) {
            return highlight
        }
        return items.first
    }

    var body: some View {
        let rows = listed
        let active = current
        VStack(alignment: .leading, spacing: 0) {
            MentionField(
                text: $query,
                placeholder: String(localized: "Search tabs"),
                fontSize: 13,
                isFocused: true,
                accessibilityLabel: String(localized: "Search tabs"),
                onSubmit: submit,
                onCancel: onCancel,
                onMove: move(by:jumping:)
            )
            .frame(height: 22)
            .padding(.horizontal, Self.textInset)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Self.plateRadius, style: .continuous)
                    .fill(Theme.Wash.hairline)
            )

            if !rows.isEmpty {
                sectionHeader("Tabs")
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Self.rowSpacing) {
                            ForEach(rows) { tab in
                                AssistantAttachRow(isHighlighted: active == .tab(tab.id)) {
                                    AssistantAttachTabLabel(tab: tab)
                                } onHover: {
                                    highlight = .tab(tab.id)
                                } action: {
                                    onAttachTab(tab)
                                }
                                .id(Item.tab(tab.id))
                            }
                        }
                    }
                    .onChange(of: active) { _, item in
                        if let item {
                            proxy.scrollTo(item)
                        }
                    }
                }
                .frame(height: tabListHeight(rows: rows.count))
                .scrollBounceBehavior(.basedOnSize)

                if rows.count < matches.count {
                    AssistantAttachRow(isHighlighted: active == .viewMore) {
                        Text("View More")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    } onHover: {
                        highlight = .viewMore
                    } action: {
                        activate(.viewMore)
                    }
                    .padding(.top, Self.rowSpacing)
                }

                Divider()
                    .padding(.horizontal, Self.textInset)
                    .padding(.top, Self.inset)
            }

            sectionHeader("Files")
            AssistantAttachRow(isHighlighted: active == .upload) {
                Text("Choose Files…")
                Spacer(minLength: 0)
            } onHover: {
                highlight = .upload
            } action: {
                activate(.upload)
            }
        }
        .padding(Self.inset)
        .frame(width: Self.width, alignment: .leading)
        .onChange(of: query) { _, _ in highlight = nil }
    }

    private func tabListHeight(rows: Int) -> CGFloat {
        let shown = CGFloat(min(rows, Self.visibleRows))
        return shown * Self.rowHeight + (shown - 1) * Self.rowSpacing
    }

    private func sectionHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(Theme.Font.badge)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Self.textInset)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func submit() {
        if let current {
            activate(current)
        }
    }

    private func activate(_ item: Item) {
        switch item {
        case .tab(let id):
            if let tab = listed.first(where: { $0.id == id }) {
                onAttachTab(tab)
            }
        case .viewMore:
            highlight = nil
            isExpanded = true
        case .upload:
            onChooseFiles()
        }
    }

    private func move(by step: Int, jumping: Bool) {
        let items = items
        guard !items.isEmpty else { return }
        if jumping {
            highlight = step < 0 ? items.first : items.last
            return
        }
        let index = current.flatMap(items.firstIndex(of:)) ?? 0
        highlight = items[(index + step + items.count) % items.count]
    }
}

private struct AssistantAttachTabLabel: View {
    let tab: BrowserTab

    private var host: String? {
        URL(string: tab.urlString)?.displayHost
    }

    var body: some View {
        OmniboxFavicon(host: host ?? "", fallback: "square.on.square", size: 13, isSelected: false)

        Text(verbatim: tab.title)
            .lineLimit(1)

        if let host {
            Text(verbatim: host)
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .layoutPriority(-1)
        }

        Spacer(minLength: 0)
    }
}

private struct AssistantAttachRow<Label: View>: View {
    let isHighlighted: Bool
    @ViewBuilder let label: () -> Label
    let onHover: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                label()
            }
            .font(Theme.Font.body)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .hoverBackground(
                isActive: isHighlighted,
                in: RoundedRectangle(cornerRadius: AssistantAttachMenu.plateRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
    }
}
