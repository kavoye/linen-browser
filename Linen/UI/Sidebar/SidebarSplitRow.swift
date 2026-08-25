// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

nonisolated enum SplitRowInteraction: Equatable {
    case wholeRow
    case perPane

    static func mode(isOnScreen: Bool) -> SplitRowInteraction {
        isOnScreen ? .perPane : .wholeRow
    }

    static func activationTarget(clicked: UUID, leader: UUID, mode: SplitRowInteraction) -> UUID {
        mode == .wholeRow ? leader : clicked
    }
}

struct SidebarSplitRow: View {
    let leading: BrowserTab
    let split: TabSplit
    let depth: Int
    let context: SidebarRowContext

    private var browser: BrowserModel {
        context.browser
    }
    private var coordinator: AppCoordinator {
        context.coordinator
    }
    private var item: SidebarItem {
        .tab(leading.id)
    }

    private static let lineHeight: CGFloat = 28

    private var isLifted: Bool {
        context.isLifted(item)
    }
    private var isArmed: Bool {
        context.isArmed(item)
    }

    @State private var hoveringRow = false

    private var interaction: SplitRowInteraction {
        .mode(isOnScreen: isOnScreen)
    }

    private var isSelected: Bool {
        split.tabs.contains { context.isSelected(.tab($0)) }
    }

    private var isOnScreen: Bool {
        guard case .tab = coordinator.sidebarDestination else { return false }
        return browser.isVisibleInSplit(leading)
    }

    private var radius: CGFloat {
        depth == 0 ? Theme.Radius.hover : FolderSection.rowRadius(depth: depth - 1)
    }

    private var lineCount: Int {
        split.sidebarLineCount
    }

    private var height: CGFloat {
        lineCount > 1 ? Self.lineHeight * CGFloat(lineCount) + CGFloat(lineCount - 1) : 32
    }

    private var carried: [SidebarItem] {
        browser.withSplitMembers([item])
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = SplitLayout(grid: split.sidebarShape, size: proxy.size, gutter: 1)
            ZStack(alignment: .topLeading) {
                ForEach(split.tabs, id: \.self) { id in
                    if let tab = browser.tab(id: id), let rect = layout.slot(of: id) {
                        SplitRowCell(
                            tab: tab,
                            shape: hoverShape(for: rect, in: proxy.size),
                            isNarrow: rect.width < 68,
                            answersAlone: interaction == .perPane,
                            context: context,
                            onTap: tapped
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    }
                }
                ForEach(layout.seams) { seam in
                    seamLine(seam)
                }
            }
        }
        .frame(height: height)
        .sidebarRowSelectionEffect(
            isSelected: isOnScreen || isSelected,
            isHovering: interaction == .wholeRow && hoveringRow,
            isDropTarget: isArmed,
            isDropCandidate: context.isFoldCandidate(item),
            radius: radius
        )
        .opacity(isLifted ? 0 : 1)
        .contentShape(Rectangle())
        .onHover { over in
            withAnimation(Theme.Motion.quick) { hoveringRow = over }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(context.space)) } action: {
            context.frames.record(item, at: $0)
        }
        .contextMenu { menu }
    }

    private func seamLine(_ seam: SplitSeam) -> some View {
        Color.clear
            .frame(width: seam.rect.width, height: seam.rect.height)
            .overlay {
                Rectangle()
                    .fill(Theme.Wash.strong)
                    .frame(
                        width: seam.axis == .sideBySide ? 1 : max(0, seam.rect.width - 14),
                        height: seam.axis == .sideBySide ? min(14, seam.rect.height) : 1
                    )
            }
            .offset(x: seam.rect.minX, y: seam.rect.minY)
    }

    private func hoverShape(for rect: CGRect, in size: CGSize) -> UnevenRoundedRectangle {
        let left = rect.minX < 0.5
        let right = rect.maxX > size.width - 0.5
        let top = rect.minY < 0.5
        let bottom = rect.maxY > size.height - 0.5
        return UnevenRoundedRectangle(
            topLeadingRadius: left && top ? radius : 0,
            bottomLeadingRadius: left && bottom ? radius : 0,
            bottomTrailingRadius: right && bottom ? radius : 0,
            topTrailingRadius: right && top ? radius : 0
        )
    }

    private func tapped(_ tab: BrowserTab) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift) {
            context.selection.hold(context.activeItem)
            context.selection.extend(to: item, in: browser.sidebarTree) {
                browser.folder(id: $0)?.isExpanded ?? false
            }
        } else if modifiers.contains(.command) {
            context.selection.hold(context.activeItem)
            context.selection.toggle(item)
        } else {
            context.selection.anchor(on: item)
            let target = SplitRowInteraction.activationTarget(
                clicked: tab.id,
                leader: leading.id,
                mode: interaction
            )
            if let opened = browser.tab(id: target) {
                coordinator.openTab(opened)
            }
        }
    }

    private var panes: [BrowserTab] {
        split.tabs.compactMap { browser.tab(id: $0) }
    }

    @ViewBuilder
    private var menu: some View {
        SidebarLinkMenuItems(tabs: panes, coordinator: coordinator)

        if let axis = split.axis {
            Button {
                browser.setSplitAxis(axis == .stacked ? .sideBySide : .stacked, containing: leading)
            } label: {
                if axis == .stacked {
                    Label("Place Side by Side", systemImage: "rectangle.split.2x1")
                } else {
                    Label("Stack Pages", systemImage: "rectangle.split.2x1")
                }
            }
        }
        Button {
            browser.dissolveSplit(containing: leading)
        } label: {
            Label("Exit Split", systemImage: "rectangle")
        }
        Divider()

        SidebarFolderMenuItems(items: carried, browser: browser)

        Button(role: .destructive) {
            for tab in panes.reversed() {
                browser.close(tab)
            }
        } label: {
            Label("Close These Tabs", systemImage: "xmark")
        }
    }
}

private struct SplitRowCell: View {
    let tab: BrowserTab
    let shape: UnevenRoundedRectangle
    let isNarrow: Bool
    let answersAlone: Bool
    let context: SidebarRowContext
    let onTap: (BrowserTab) -> Void

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false
    @State private var controlsWidth: CGFloat = 0

    private var browser: BrowserModel {
        context.browser
    }
    private var coordinator: AppCoordinator {
        context.coordinator
    }

    private var isFocused: Bool {
        coordinator.sidebarDestination == .tab(tab.id) && browser.isVisibleInSplit(tab)
    }

    private var showsPinReturn: Bool {
        sidebarStyle == .full && tab.isAwayFromPin && hovering && answersAlone
    }

    private var titleMask: some View {
        let covered = answersAlone && hovering ? controlsWidth : 0
        return HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: covered > 0 ? 14 : 0)
            Color.clear
                .frame(width: covered)
        }
    }

    var body: some View {
        HStack(spacing: SidebarMetrics.rowIconSpacing) {
            if showsPinReturn {
                SplitRowPinReturn(help: String(localized: "Back to \(pinnedPageName(of: tab))")) {
                    browser.returnToPin(tab)
                }
            } else if sidebarStyle == .full, tab.isPlayingAudio || tab.isMuted {
                SidebarTabMuteButton(isMuted: tab.isMuted) {
                    coordinator.toggleMute(tab: tab)
                }
            } else {
                TabIcon(tab: tab)
            }

            if sidebarStyle == .full, !isNarrow {
                Text(verbatim: tab.title)
                    .font(Theme.Font.control)
                    .foregroundStyle(isFocused ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask(alignment: .leading) { titleMask }
            }
        }
        .overlay(alignment: .trailing) {
            if sidebarStyle == .full, answersAlone {
                CloseButton { browser.close(tab) }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                        controlsWidth = min($0, 20)
                    }
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
        }
        .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sidebarHoverFill(isHovering: answersAlone && hovering, in: shape)
        .contentShape(Rectangle())
        .onTapGesture { onTap(tab) }
        .onMiddleClick {
            coordinator.tabPreview.dismiss()
            browser.close(tab)
        }
        .onHover { over in
            withAnimation(Theme.Motion.quick) { hovering = over }
        }
        .help(Text(verbatim: tab.title))
    }
}

private struct SplitRowPinReturn: View {
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(Theme.Font.badge)
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: SidebarMetrics.rowIconSize, height: SidebarMetrics.rowIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(Theme.Motion.quick) { hovering = over }
        }
        .help(Text(verbatim: help))
    }
}
