// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

func pinnedPageName(of tab: BrowserTab) -> String {
    if !tab.pinnedTitle.isEmpty {
        return tab.pinnedTitle
    }
    return tab.pinnedURL?.host() ?? String(localized: "the bookmarked page")
}

struct SidebarTabRow: View {
    let tab: BrowserTab
    let depth: Int
    let context: SidebarRowContext

    private var browser: BrowserModel {
        context.browser
    }
    private var coordinator: AppCoordinator {
        context.coordinator
    }
    private var item: SidebarItem {
        .tab(tab.id)
    }
    private var isLifted: Bool {
        context.isLifted(item)
    }
    private var isArmed: Bool {
        context.isArmed(item)
    }
    private var armedSplitEdge: HorizontalEdge? {
        context.armedSplitEdge(item)
    }
    private var isSelected: Bool {
        context.isSelected(item)
    }
    private var isActive: Bool {
        coordinator.sidebarDestination == .tab(tab.id)
    }

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false
    @State private var windowFrame: CGRect = .zero
    @State private var controlsWidth: CGFloat = 0

    private var showsTrailingControls: Bool {
        hovering || isActive
    }

    private var showsPinSegment: Bool {
        sidebarStyle == .full && tab.isAwayFromPin
    }

    private var returnHelp: Text {
        Text("Back to \(pinnedPageName(of: tab))")
    }

    private var showsHoverPreview: Bool {
        tab.internalPage == nil && !tab.urlString.isEmpty
    }

    private var helpText: Text {
        if isActive, tab.isAwayFromPin {
            return returnHelp
        }
        guard sidebarStyle == .icons, isActive || !showsHoverPreview else { return Text(verbatim: "") }
        return Text(verbatim: tab.title)
    }

    private func tapped() {
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
            activate()
        }
    }

    private func activate() {
        coordinator.tabPreview.dismiss()
        if isActive, tab.isAwayFromPin {
            browser.returnToPin(tab)
        } else {
            coordinator.openTab(tab)
        }
    }

    private var selected: [SidebarItem] {
        guard context.selection.count > 1, isSelected else { return [] }
        return Array(context.selection.items)
    }

    private var trailingControls: some View {
        Group {
            if tab.pinnedURL == nil {
                CloseButton {
                    browser.close(tab)
                }
            } else {
                ChromeIcon.rowControl(symbol: "minus", help: String(localized: "Remove Bookmark")) {
                    browser.unpin(tab)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlsWidth = min($0, 20) }
        .opacity(showsTrailingControls ? 1 : 0)
        .allowsHitTesting(showsTrailingControls)
    }

    private func splitEnd(_ edge: HorizontalEdge) -> some View {
        let opacity: Double = if armedSplitEdge == edge {
            0.85
        } else if context.candidateSplitEdge(item) == edge {
            0.45
        } else {
            0.15
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: edge == .leading ? Theme.Radius.hover : 0,
            bottomLeadingRadius: edge == .leading ? Theme.Radius.hover : 0,
            bottomTrailingRadius: edge == .trailing ? Theme.Radius.hover : 0,
            topTrailingRadius: edge == .trailing ? Theme.Radius.hover : 0
        )
        .fill(Theme.accent.opacity(opacity))
        .frame(width: SidebarMetrics.splitEndWidth(style: sidebarStyle))
        .allowsHitTesting(false)
    }

    private var titleMask: some View {
        let covered = showsTrailingControls ? controlsWidth : 0
        return HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: covered > 0 ? 18 : 0)
            Color.clear
                .frame(width: covered)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsPinSegment {
                PinReturnSegment(tab: tab, help: returnHelp) {
                    coordinator.tabPreview.dismiss()
                    browser.returnToPin(tab)
                    coordinator.showBrowserPage()
                }
                Rectangle()
                    .fill(Theme.Wash.strong)
                    .frame(width: 1, height: 14)
            }

            HStack(spacing: SidebarMetrics.rowIconSpacing) {
                if sidebarStyle == .full, tab.isPlayingAudio || tab.isMuted {
                    SidebarTabMuteButton(isMuted: tab.isMuted) {
                        coordinator.toggleMute(tab: tab)
                    }
                } else {
                    TabIcon(tab: tab)
                }

                if sidebarStyle == .full {
                    Text(verbatim: tab.title)
                        .font(Theme.Font.title)
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .mask(alignment: .leading) { titleMask }
                }
            }
            .overlay(alignment: .trailing) {
                if sidebarStyle == .full {
                    trailingControls
                }
            }
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity)
        }
        .frame(height: 32)
        .help(helpText)
        .sidebarRowSelectionEffect(
            isSelected: isActive || isSelected,
            isHovering: hovering,
            isDropTarget: isArmed,
            isDropCandidate: context.isFoldCandidate(item),
            radius: depth == 0 ? Theme.Radius.hover : FolderSection.rowRadius(depth: depth - 1)
        )
        .overlay {
            if context.showsSplitEdges(item) {
                HStack(spacing: 0) {
                    splitEnd(.leading)
                    Spacer(minLength: 0)
                    splitEnd(.trailing)
                }
            }
        }
        .opacity(isLifted ? 0 : 1)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(context.space)) } action: {
            context.frames.record(item, at: $0)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            windowFrame = frame
            coordinator.tabPreview.moved(tab.id, anchor: frame)
        }
        .hoverVerified($hovering) { coordinator.tabPreview.unhover(tab.id) }
        .onTapGesture { tapped() }
        .onMiddleClick {
            coordinator.tabPreview.dismiss()
            browser.close(tab)
        }
        .onHover { over in
            withAnimation(Theme.Motion.quick) { hovering = over }
            if over, !isActive, showsHoverPreview {
                coordinator.tabPreview.hover(tab, anchor: windowFrame)
            } else {
                coordinator.tabPreview.unhover(tab.id)
            }
        }
        .onDisappear { coordinator.tabPreview.unhover(tab.id) }
        .contextMenu {
            if selected.isEmpty {
                menu
            } else {
                SidebarSelectionMenuItems(items: selected, browser: browser)
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            coordinator.copyLink(for: tab)
        } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
        .disabled(coordinator.linkURL(for: tab) == nil)
        Divider()
        Button {
            browser.duplicate(tab)
        } label: {
            Label("Duplicate Tab", systemImage: "plus.square.on.square")
        }
        if let anchor = browser.activeTab, anchor !== tab {
            Button {
                coordinator.split(anchor, with: tab, axis: .sideBySide)
            } label: {
                Label("Open Beside Current Page", systemImage: "rectangle.split.2x1")
            }
        }
        if browser.splits.contains(tab.id) {
            Button {
                browser.dissolveSplit(containing: tab)
            } label: {
                Label("Exit Split", systemImage: "rectangle")
            }
        }
        Divider()
        if tab.pinnedURL == nil {
            Button {
                browser.pin(tab)
            } label: {
                Label("Bookmark This Page", systemImage: "bookmark")
            }
        } else {
            if tab.isAwayFromPin {
                Button {
                    browser.returnToPin(tab)
                } label: {
                    Label("Back to Bookmarked Page", systemImage: "arrow.uturn.backward")
                }
                Divider()
                Button {
                    browser.pin(tab)
                } label: {
                    Label("Move Bookmark to This Page", systemImage: "bookmark")
                }
            }
            Button {
                browser.unpin(tab)
            } label: {
                Label("Remove Bookmark", systemImage: "bookmark.slash")
            }
        }
        Divider()
        SidebarFolderMenuItems(items: [item], browser: browser)
        Divider()
        Button(role: .destructive) {
            browser.close(tab)
        } label: {
            Label("Close Tab", systemImage: "xmark")
        }
    }
}

struct SidebarSelectionMenuItems: View {
    let items: [SidebarItem]
    let browser: BrowserModel

    var body: some View {
        SidebarFolderMenuItems(items: items, browser: browser)
        Button(role: .destructive) {
            let count = browser.tabCount(in: items)
            Task {
                guard await ConfirmAlert.destructive(
                    "Close \(count) tabs?",
                    verb: "Close Tabs"
                ) else { return }
                browser.close(items)
            }
        } label: {
            Label("Close \(browser.tabCount(in: items)) Tabs", systemImage: "xmark")
        }
    }
}

struct SidebarFolderMenuItems: View {
    let items: [SidebarItem]
    let browser: BrowserModel

    private var isFiled: Bool {
        items.contains { browser.sidebarTree.parent(of: $0) != nil }
    }

    var body: some View {
        Menu {
            ForEach(browser.folders) { folder in
                Button {
                    browser.move(items, into: folder)
                } label: {
                    Text(verbatim: folder.name)
                }
            }
            Divider()
            Button {
                browser.createFolder(containing: items)
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        if isFiled {
            Button {
                browser.moveOut(items)
            } label: {
                Label("Remove from Folder", systemImage: "folder.badge.minus")
            }
        }
    }
}

private struct PinReturnSegment: View {
    let tab: BrowserTab
    let help: Text
    let action: () -> Void

    @State private var hovering = false
    @State private var pinnedFavicon: NSImage?

    private var isSameSite: Bool {
        guard let pinnedHost = tab.pinnedURL?.host()?.lowercased() else { return false }
        return URL(string: tab.urlString)?.host()?.lowercased() == pinnedHost
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let pinnedFavicon, !isSameSite {
                    Image(nsImage: pinnedFavicon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tight))
                        .opacity(hovering ? 0 : 1)
                }
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering || isSameSite || pinnedFavicon == nil ? 1 : 0)
            }
            .frame(width: 34, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.Radius.hover,
                bottomLeadingRadius: Theme.Radius.hover
            )
            .fill(hovering ? Theme.Wash.hover : Theme.Wash.none)
        )
        .onHover { over in
            withAnimation(Theme.Motion.quick) { hovering = over }
        }
        .help(help)
        .task(id: tab.pinnedURL) {
            pinnedFavicon = nil
            guard let host = tab.pinnedURL?.host() else { return }
            if let cached = FaviconLoader.shared.cached(for: host) {
                pinnedFavicon = cached
            } else {
                pinnedFavicon = await FaviconLoader.shared.load(forHost: host)
            }
        }
    }
}

struct SidebarTabMuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    private var help: LocalizedStringResource {
        isMuted ? "Unmute Tab" : "Mute Tab"
    }

    var body: some View {
        ChromeIcon(
            symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            isSubdued: isMuted,
            help: String(localized: help),
            action: action
        )
    }
}

struct PinBadge: View {
    let browser: BrowserModel

    @State private var hovering = false

    private var tab: BrowserTab? {
        browser.activeTab
    }
    private var hasPage: Bool {
        !(tab?.urlString.isEmpty ?? true)
    }

    var body: some View {
        if let tab, hasPage {
            ChromeIcon(
                symbol: symbol(for: tab),
                weight: .semibold,
                help: helpText(for: tab)
            ) {
                if tab.isAwayFromPin {
                    browser.returnToPin(tab)
                } else if tab.isShowingPin {
                    browser.unpin(tab)
                } else {
                    browser.pin(tab)
                }
            }
            .animation(.snappy(duration: 0.2), value: tab.pinnedURL)
        }
    }

    private func symbol(for tab: BrowserTab) -> String {
        if tab.isAwayFromPin {
            return "arrow.uturn.backward"
        }
        return tab.isShowingPin ? "bookmark.fill" : "bookmark"
    }

    private func helpText(for tab: BrowserTab) -> String {
        if tab.isAwayFromPin {
            return String(localized: "Back to \(pinnedPageName(of: tab))")
        }
        let help: LocalizedStringResource = tab.isShowingPin
            ? "Remove Bookmark"
            : "Bookmark This Page in the Tab"
        return String(localized: help)
    }
}

struct TabIcon: View {
    let tab: BrowserTab
    var size: CGFloat = SidebarMetrics.rowIconSize

    static func isAsleep(_ state: TabReclaimState) -> Bool {
        state == .unloaded
    }

    static let asleepDim: Double = 0.4

    private var isAsleep: Bool {
        Self.isAsleep(tab.reclaimState)
    }

    var body: some View {
        Group {
            if let internalPage = tab.internalPage {
                Image(systemName: internalPage.symbol)
                    .font(.system(size: size * 0.72, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if tab.isLoading, !tab.isRestoring {
                Spinner(size: size * 0.8)
                    .foregroundStyle(.secondary)
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size - 1, height: size - 1)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tight))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.69))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .saturation(isAsleep ? 0 : 1)
        .opacity(isAsleep ? Self.asleepDim : 1)
        .overlay(alignment: .bottomTrailing) {
            if isAsleep {
                UnloadedTabBadge(size: size * 0.56)
                    .offset(x: size * 0.12, y: size * 0.12)
            }
        }
    }
}
