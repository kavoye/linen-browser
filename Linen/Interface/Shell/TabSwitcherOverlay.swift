// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct TabSwitcherOverlay: View {
    let browser: BrowserModel
    let onClose: (BrowserTab) -> Void
    let onToggleMute: (BrowserTab) -> Void

    @State private var isRevealed = false
    @State private var hoveredID: UUID?
    @State private var scroll = ScrollPosition(edge: .leading)
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.floatingGround) private var floatingGround

    private static let revealDelay: Duration = .milliseconds(150)
    private static let spacing: CGFloat = 16
    private static let padding: CGFloat = 18
    private static let margin: CGFloat = 24
    private static let maxCards = 7

    var body: some View {
        GeometryReader { proxy in
            if isRevealed {
                let order = browser.switcherTabs
                let width = Self.rowWidth(count: order.count, available: proxy.size.width)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Self.spacing) {
                        ForEach(order) { tab in
                            TabSwitcherCard(
                                tab: tab,
                                isSelected: tab.id == browser.switcherSelection,
                                isHovered: tab.id == hoveredID,
                                onClose: { onClose(tab) },
                                onToggleMute: { onToggleMute(tab) }
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
                }
                .scrollPosition($scroll)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                    scrollOffset = x
                }
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onAppear { reveal(browser.switcherSelection, in: order, viewport: width, animated: false) }
                .onChange(of: browser.switcherSelection) { _, id in
                    reveal(id, in: order, viewport: width, animated: true)
                }
                .background { surface }
                .clipShape(Self.shape)
                .overlay {
                    if let floatingGround {
                        Self.shape.strokeBorder(floatingGround.ink.opacity(0.1), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 44, y: 18)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .task {
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
    }

    @ViewBuilder private var surface: some View {
        if let floatingGround {
            FloatingChromeFill(shape: Self.shape, ground: floatingGround)
        } else {
            Self.shape
                .fill(.clear)
                .glassEffect(.regular, in: Self.shape)
        }
    }

    private func reveal(_ id: UUID?, in order: [BrowserTab], viewport: CGFloat, animated: Bool) {
        guard let index = order.firstIndex(where: { $0.id == id }),
              let target = Self.offset(revealing: index, from: scrollOffset, viewport: viewport)
        else { return }
        withAnimation(animated ? .easeOut(duration: 0.18) : nil) {
            scroll.scrollTo(x: target)
        }
    }

    static func offset(revealing index: Int, from current: CGFloat, viewport: CGFloat) -> CGFloat? {
        let leading = CGFloat(index) * (TabSwitcherCard.outerWidth + spacing)
        let trailing = leading + TabSwitcherCard.outerWidth + 2 * padding
        if leading < current {
            return leading
        }
        if trailing > current + viewport {
            return trailing - viewport
        }
        return nil
    }

    static func rowWidth(count: Int, available: CGFloat) -> CGFloat {
        let cards = CGFloat(min(count, maxCards))
        let content = cards * TabSwitcherCard.outerWidth + max(cards - 1, 0) * spacing + 2 * padding
        return max(0, min(content, available - 2 * margin))
    }
}

private struct TabSwitcherCard: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool
    let onClose: () -> Void
    let onToggleMute: () -> Void

    static let width: CGFloat = 216
    private static let imageHeight: CGFloat = 135
    private static let ring: CGFloat = 2.5
    static let outerWidth = width + 2 * (ring + 1)

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            face
                .frame(width: Self.width, height: Self.imageHeight)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(Theme.Wash.hairline, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if isHovered {
                        TabSwitcherChipButton(symbol: "xmark", help: String(localized: "Close Tab"), action: onClose)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if tab.isPlayingAudio || tab.isMuted {
                        TabSwitcherChipButton(
                            symbol: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            help: String(localized: muteHelp),
                            action: onToggleMute
                        )
                        .padding(6)
                    }
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
                    .font(Theme.Font.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Self.ring + 2)
            .frame(width: Self.outerWidth, alignment: .leading)
        }
    }

    private var muteHelp: LocalizedStringResource {
        tab.isMuted ? "Unmute Tab" : "Mute Tab"
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
                .frame(width: 36, height: 36)
                .frame(width: Self.width, height: Self.imageHeight)
                .background(Theme.Wash.hairline)
        } else {
            banner(Image(systemName: "globe"))
        }
    }

    private func banner(_ symbol: Image) -> some View {
        symbol
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: Self.width, height: Self.imageHeight)
            .background(Theme.Wash.hairline)
    }
}

private struct TabSwitcherChipButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .contentTransition(.identity)
                .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                .opacity(hovering ? 0.95 : 0.7)
                .frame(width: 20, height: 20)
                .background(scheme == .dark ? Color(white: 0.18) : Color(white: 0.96), in: shape)
                .overlay { shape.strokeBorder(Theme.Wash.hairline, lineWidth: 1) }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
