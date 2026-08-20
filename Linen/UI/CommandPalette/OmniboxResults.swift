// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct OmniboxList: View {
    enum Density {
        case compact
        case regular

        var rowHeight: CGFloat {
            self == .compact ? 28 : 40
        }
        var stackedRowHeight: CGFloat {
            self == .compact ? 40 : 50
        }

        func rowHeight(for item: OmniboxItem) -> CGFloat {
            item.kind.stacksDetail ? stackedRowHeight : rowHeight
        }

        var headerHeight: CGFloat {
            self == .compact ? 20 : 26
        }
        var sectionGap: CGFloat {
            self == .compact ? 4 : 6
        }
        var titleSize: CGFloat {
            self == .compact ? 12.5 : 14
        }
        var detailSize: CGFloat {
            self == .compact ? 11 : 12
        }
        var padding: CGFloat {
            self == .compact ? 6 : 8
        }
    }

    let sections: [OmniboxSection]
    let query: String
    let selection: Int
    var density: Density = .regular
    /// A scrolling container sets this false and uses `.contentMargins`.
    /// `scrollTo` cannot see padding inside the content, so it brings the row
    /// flush to the edge and leaves the inset off screen.
    var insetsVertically = true
    var containerRadius: CGFloat = Theme.Radius.panel
    let onSelect: (Int) -> Void
    let onRun: (Int) -> Void

    @State private var pointerAnchor: CGPoint?

    private func hovered(_ index: Int) {
        let pointer = NSEvent.mouseLocation
        guard pointerAnchor != pointer else { return }
        pointerAnchor = nil
        onSelect(index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.section.id) { group in
                ForEach(group.section.items.enumerated(), id: \.element.id) { offset, item in
                    let index = group.start + offset
                    VStack(alignment: .leading, spacing: 0) {
                        if offset == 0 {
                            heading(group.section, isFirst: group.start == 0)
                        }

                        OmniboxRow(
                            item: item,
                            query: query,
                            isSelected: index == selection,
                            density: density,
                            cornerRadius: Theme.Radius.nested(in: containerRadius, inset: density.padding)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onRun(index) }
                        .onHover { if $0 { hovered(index) } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: item.title))
                        .accessibilityValue(Text(verbatim: [item.detail, item.shortcut]
                            .filter { !$0.isEmpty }
                            .joined(separator: ", ")))
                        .accessibilityAddTraits(index == selection ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityAction { onRun(index) }
                    }
                    .id(index)
                }
            }
        }
        .padding(.horizontal, density.padding)
        .padding(.vertical, insetsVertically ? density.padding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selection) { _, _ in
            pointerAnchor = NSEvent.mouseLocation
        }
    }

    @ViewBuilder
    private func heading(_ section: OmniboxSection, isFirst: Bool) -> some View {
        if !section.title.isEmpty {
            HStack(alignment: .bottom, spacing: 8) {
                Text(verbatim: section.title)
                    .font(.system(size: density == .compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(.tertiary)

                if !section.hint.isEmpty {
                    Spacer(minLength: 8)
                    Text(verbatim: section.hint)
                        .font(.system(size: density == .compact ? 10 : 11))
                        .foregroundStyle(.quaternary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, density == .compact ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: density.headerHeight, alignment: .leading)
            .padding(.top, isFirst ? 0 : density.sectionGap)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var groups: [(section: OmniboxSection, start: Int)] {
        var start = 0
        var result: [(OmniboxSection, Int)] = []
        for section in sections {
            result.append((section, start))
            start += section.items.count
        }
        return result
    }

    static func height(of sections: [OmniboxSection], density: Density) -> CGFloat {
        let rows = sections.flatMap(\.items).reduce(CGFloat(0)) { $0 + density.rowHeight(for: $1) }
        let headers = sections.filter { !$0.title.isEmpty }.count
        return rows
            + CGFloat(headers) * density.headerHeight
            + CGFloat(max(0, sections.count - 1)) * density.sectionGap
            + density.padding * 2
    }
}

struct OmniboxFavicon: View {
    let host: String
    let fallback: String
    let size: CGFloat
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
        .task(id: host) {
            if let hit = FaviconLoader.shared.cached(for: host) {
                image = hit
                return
            }
            image = await FaviconLoader.shared.load(forHost: host)
        }
    }
}

private struct OmniboxRow: View {
    let item: OmniboxItem
    let query: String
    let isSelected: Bool
    let density: OmniboxList.Density
    let cornerRadius: CGFloat

    private var iconWidth: CGFloat {
        density == .compact ? 16 : 20
    }

    var body: some View {
        HStack(spacing: density == .compact ? 8 : 11) {
            icon

            if item.kind.stacksDetail {
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: density.titleSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(verbatim: item.detail)
                        .font(.system(size: density.detailSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                title
                    .font(.system(size: density.titleSize))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !item.detail.isEmpty {
                    Text(verbatim: item.detail)
                        .font(.system(size: density.detailSize))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if !item.shortcut.isEmpty {
                Text(verbatim: item.shortcut)
                    .font(.system(size: density.detailSize, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, density == .compact ? 8 : 10)
        .frame(height: density.rowHeight(for: item))
        .background(
            isSelected ? AnyShapeStyle(Theme.Wash.hover) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }

    @ViewBuilder
    private var icon: some View {
        if item.kind == .ask {
            ProviderBrandIcon(
                providerID: ProviderCatalog.shared.selected.id,
                size: density == .compact ? 13 : 16
            )
            .frame(width: iconWidth)
        } else if let host = item.iconHost {
            OmniboxFavicon(
                host: host,
                fallback: item.symbol,
                size: density == .compact ? 15 : 18,
                isSelected: isSelected
            )
            .frame(width: iconWidth)
        } else {
            symbolIcon
        }
    }

    private var symbolIcon: some View {
        Image(systemName: item.symbol)
            .font(.system(size: density == .compact ? 11 : 13))
            .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(width: iconWidth)
    }

    private var title: Text {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.kind == .phrase,
              !typed.isEmpty,
              item.title.lowercased().hasPrefix(typed.lowercased())
        else {
            return Text(verbatim: item.title)
        }
        var head = AttributedString(item.title.prefix(typed.count))
        head.foregroundColor = .secondary
        var tail = AttributedString(item.title.dropFirst(typed.count))
        tail.foregroundColor = .primary
        return Text(head + tail)
    }
}
