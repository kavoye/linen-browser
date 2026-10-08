// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct TabSwitcherOverlay: View {
    let browser: BrowserModel

    @State private var isRevealed = false
    @State private var hoveredID: UUID?

    private static let revealDelay: Duration = .milliseconds(150)
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 14
    private static let margin: CGFloat = 24
    private static let maxCards = 7

    var body: some View {
        GeometryReader { proxy in
            if isRevealed {
                let order = browser.switcherTabs
                let selected = order.firstIndex { $0.id == browser.switcherSelection }
                let shown = Self.window(count: order.count, selected: selected ?? 0, fitting: Self.capacity(proxy.size.width))
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(order[shown]) { tab in
                        TabSwitcherCard(
                            tab: tab,
                            isSelected: tab.id == browser.switcherSelection,
                            isHovered: tab.id == hoveredID
                        )
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                hoveredID = tab.id
                            } else if hoveredID == tab.id {
                                hoveredID = nil
                            }
                        }
                        .onTapGesture { browser.endTabSwitching(choosing: tab.id) }
                    }
                }
                .padding(Self.padding)
                .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.popover, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .task {
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }

    private static func capacity(_ width: CGFloat) -> Int {
        let room = width - 2 * (margin + padding) + spacing
        let fits = Int(room / (TabSwitcherCard.outerWidth + spacing))
        return min(max(fits, 1), maxCards)
    }

    static func window(count: Int, selected: Int, fitting capacity: Int) -> Range<Int> {
        guard count > capacity else { return 0..<count }
        let start = min(max(selected - capacity / 2, 0), count - capacity)
        return start..<(start + capacity)
    }
}

private struct TabSwitcherCard: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool

    static let width: CGFloat = 168
    private static let imageHeight: CGFloat = 105
    private static let ring: CGFloat = 2.5
    static let outerWidth = width + 2 * (ring + 1)

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            face
                .frame(width: Self.width, height: Self.imageHeight)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(Theme.Wash.hairline, lineWidth: 1)
                }
                .padding(Self.ring + 1)
                .overlay {
                    if isSelected || isHovered {
                        RoundedRectangle(cornerRadius: Theme.Radius.card + Self.ring + 1, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary), lineWidth: Self.ring)
                    }
                }

            HStack(spacing: 6) {
                TabFaviconMark(tab: tab)

                Text(verbatim: tab.title)
                    .font(Theme.Font.label.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Self.ring + 2)
            .frame(width: Self.outerWidth, alignment: .leading)
        }
    }

    @ViewBuilder private var face: some View {
        if let page = tab.internalPage {
            banner(Image(systemName: page.symbol))
        } else if SystemPages.showsStartFace(tab) {
            banner(Image(systemName: SystemPages.startSymbol))
        } else if let preview = tab.preview {
            Image(nsImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: Self.width, height: Self.imageHeight, alignment: .top)
                .clipped()
                .saturation(TabIcon.isAsleep(tab.reclaimState) ? 0 : 1)
        } else if let favicon = tab.favicon {
            FaviconImage(image: favicon)
                .frame(width: 28, height: 28)
                .frame(width: Self.width, height: Self.imageHeight)
                .background(Theme.Wash.hairline)
        } else {
            banner(Image(systemName: "globe"))
        }
    }

    private func banner(_ symbol: Image) -> some View {
        symbol
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: Self.width, height: Self.imageHeight)
            .background(Theme.Wash.hairline)
    }
}
