// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct Sidebar: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    @Environment(\.windowControlsInset) private var windowControlsInset
    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.sidebarIsFloating) private var isFloating
    @Environment(\.floatingGround) private var floatingGround
    @Environment(\.colorScheme) private var scheme
    @State private var bottomObscuredHeight: CGFloat = 0
    @State private var newFolderDrop = SidebarNewFolderDrop()
    @State private var pinDrop = SidebarPinDrop()

    private var selection: SidebarSelection {
        browser.sidebarSelection
    }

    private var frames: SidebarFrames {
        coordinator.sidebarDrag.frames
    }

    private var wearsBand: Bool {
        sidebarStyle == .icons
    }

    private var inkColor: NSColor {
        LoomChrome.sampledColor(
            ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
    }

    private var inkIsLight: Bool {
        if let floatingGround {
            return floatingGround.isLight
        }
        return Self.inkIsLight(browser: browser, coordinator: coordinator, scheme: scheme, wearsBand: wearsBand)
    }

    static func inkIsLight(
        browser: BrowserModel,
        coordinator: AppCoordinator,
        scheme: ColorScheme,
        wearsBand: Bool
    ) -> Bool {
        if !coordinator.isShowingSettings {
            return ChromeBand.loomIsLight(browser: browser, coordinator: coordinator, scheme: scheme)
        }
        guard wearsBand else { return scheme == .light }
        return PageInk.isLight(
            ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
    }

    private var topPadding: CGFloat {
        guard windowControlsInset > 0 else { return 10 }
        return sidebarStyle == .icons ? Theme.topBarHeight : 8
    }

    private var contentInsets: EdgeInsets {
        if isFloating {
            let inset = LoomChrome.canvasInset
            return EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
        }
        guard sidebarStyle == .full else {
            return EdgeInsets(top: 0, leading: LoomChrome.canvasInset, bottom: 0, trailing: 0)
        }
        let inset = SidebarMetrics.fullContentInset
        let balance = LoomChrome.sidebarContentBalanceOffset
        return EdgeInsets(
            top: 0,
            leading: inset + balance,
            bottom: 0,
            trailing: inset - balance
        )
    }

    var body: some View {
        WorkspaceList(
            browser: browser,
            coordinator: coordinator,
            selection: selection,
            newFolderDrop: newFolderDrop,
            pinDrop: pinDrop,
            frames: frames,
            bottomClearance: bottomObscuredHeight,
            topBar: SidebarTopChrome(
                browser: browser,
                coordinator: coordinator,
                selection: selection,
                newFolderDrop: newFolderDrop,
                pinDrop: pinDrop
            ),
            bottomBar: SidebarBottomChrome(
                coordinator: coordinator,
                obscuredHeight: $bottomObscuredHeight
            ),
            contentInsets: contentInsets
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
        .padding(.top, topPadding)
        .background {
            ZStack {
                if let floatingGround {
                    FloatingChromeFill(shape: LoomChrome.canvasShape, ground: floatingGround)
                } else if isFloating {
                    LoomFloatingFill(
                        sampledPageColor: ChromeBand.pageColor(
                            browser: browser,
                            coordinator: coordinator
                        ),
                        settings: coordinator.settings
                    )
                }
                WindowDragArea()
            }
        }
        .environment(\.chromeIsLight, inkIsLight)
        .environment(\.chromeWash, .of(floatingGround.map { $0.color } ?? inkColor, isLight: inkIsLight))
        .environment(\.windowColorScheme, scheme)
        .environment(\.colorScheme, inkIsLight ? .light : .dark)
        .animation(nil, value: inkIsLight)
        .animation(Theme.Motion.settle, value: coordinator.media.model.isActive)
    }
}

private struct SidebarTopChrome: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let selection: SidebarSelection
    let newFolderDrop: SidebarNewFolderDrop
    let pinDrop: SidebarPinDrop

    private var offersPin: Bool {
        coordinator.sidebarDrag.acceptsPin
    }

    var body: some View {
        VStack(spacing: 6) {
            SidebarTopRow(
                browser: browser,
                coordinator: coordinator,
                selection: selection,
                newFolderDrop: newFolderDrop
            )

            NewTabRow(coordinator: coordinator)
                .opacity(offersPin ? 0 : 1)
                .overlay {
                    if offersPin {
                        SidebarDropMark(kind: .pin, isArmed: pinDrop.isArmed)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pinDrop.frame = $0 }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SidebarBottomChrome: View {
    let coordinator: AppCoordinator
    @Binding var obscuredHeight: CGFloat

    @Environment(\.sidebarStyle) private var sidebarStyle

    private var downloadsButton: some View {
        SidebarDownloadsButton(coordinator: coordinator)
    }

    var body: some View {
        VStack(spacing: 6) {
            SidebarPinnedCards(
                coordinator: coordinator,
                obscuredHeight: $obscuredHeight
            )

            if sidebarStyle == .icons {
                VStack(spacing: 6) {
                    SidebarProfileControl(coordinator: coordinator)
                    downloadsButton
                    SidebarHistoryButton(coordinator: coordinator)
                    SidebarSettingsRow(coordinator: coordinator)
                }
            } else {
                HStack(spacing: 6) {
                    SidebarProfileControl(coordinator: coordinator)
                        .padding(.leading, SidebarMetrics.profileLeading)

                    Spacer(minLength: 0)

                    downloadsButton
                    SidebarHistoryButton(coordinator: coordinator)
                    SidebarSettingsRow(coordinator: coordinator)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SidebarPinnedCards: View {
    let coordinator: AppCoordinator
    @Binding var obscuredHeight: CGFloat

    @State private var mediaHeight: CGFloat = 0
    @State private var measuredBanner: CGFloat = 0

    private static let spacing: CGFloat = 6

    private var bannerHeight: CGFloat {
        coordinator.updates.model.isBannerVisible ? measuredBanner : 0
    }

    private var stackedHeight: CGFloat {
        let cards = [mediaHeight, bannerHeight].filter { $0 > 0 }
        guard !cards.isEmpty else { return 0 }
        return cards.reduce(0, +) + Self.spacing * CGFloat(cards.count - 1)
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            if coordinator.media.model.isActive {
                MediaSidebarCard(
                    media: coordinator.media,
                    coordinator: coordinator,
                    obscuredHeight: $mediaHeight
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            UpdateBanner(updates: coordinator.updates)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredBanner = $0 }
        }
        .frame(maxWidth: .infinity)
        .zIndex(1)
        .onAppear { obscuredHeight = stackedHeight }
        .onChange(of: stackedHeight) { _, height in obscuredHeight = height }
        .onChange(of: coordinator.media.model.isActive) { _, isActive in
            if !isActive {
                mediaHeight = 0
            }
        }
    }
}

struct SidebarTopRow: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let selection: SidebarSelection
    let newFolderDrop: SidebarNewFolderDrop

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.sidebarIsFloating) private var isFloating
    @Environment(\.sidebarTopRowShift) private var shift

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    var body: some View {
        Group {
            if sidebarStyle == .icons {
                VStack(spacing: 2) {
                    SidebarTopActions(
                        browser: browser,
                        coordinator: coordinator,
                        selection: selection,
                        newFolderDrop: newFolderDrop
                    )
                }
            } else {
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    SidebarTopActions(
                        browser: browser,
                        coordinator: coordinator,
                        selection: selection,
                        newFolderDrop: newFolderDrop
                    )
                }
            }
        }
        .padding(.bottom, 2)
        .opacity(SidebarMetrics.topControlsOpacity(isShowing: sidebar.isShowing || isFloating))
        .visualEffect { [shift] content, _ in content.offset(shift) }
    }
}

struct SidebarVisibilityToggle: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @Environment(\.windowControlsInset) private var windowControlsInset
    @Environment(\.colorScheme) private var scheme

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    private var label: LocalizedStringResource {
        sidebar.isVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    private var barColor: NSColor {
        LoomChrome.sampledColor(
            ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
    }

    private var sitsOnSidebar: Bool {
        sidebar.isShowing && sidebar.style != .icons
    }

    private var barIsLight: Bool {
        if sitsOnSidebar {
            return Sidebar.inkIsLight(browser: browser, coordinator: coordinator, scheme: scheme, wearsBand: false)
        }
        return PageInk.isLight(
            LoomChrome.sampledColor(
                ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
                scheme: scheme
            ),
            scheme: scheme
        )
    }

    var body: some View {
        ToolbarButton(
            symbol: "sidebar.left",
            enabled: true,
            isOn: sidebar.isVisible,
            highlightsWhenOn: false,
            quiet: sitsOnSidebar,
            help: String(localized: label)
        ) {
            sidebar.toggleVisible()
        }
        .onHover { if $0, !sidebar.isVisible { sidebar.isPeeking = true } }
        .contextMenu {
            SidebarStyleMenuItems(sidebar: sidebar)
        }
        .accessibilityLabel(Text(label))
        .padding(
            .leading,
            SidebarMetrics.permanentToggleLeading(windowControlsInset: windowControlsInset)
        )
        .frame(height: Theme.topBarHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.chromeIsLight, barIsLight)
        .environment(\.chromeWash, .of(barColor, isLight: barIsLight))
        .environment(\.colorScheme, barIsLight ? .light : .dark)
        .animation(nil, value: barIsLight)
    }
}

private struct SidebarTopActions: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let selection: SidebarSelection
    let newFolderDrop: SidebarNewFolderDrop

    var body: some View {
        Group {
            QuietIconButton(
                symbol: "magnifyingglass",
                isOn: false,
                help: String(localized: "Search Everything (⌘K)")
            ) {
                coordinator.openPalette()
            }
            QuietIconButton(
                symbol: "folder.badge.plus",
                isOn: newFolderDrop.isArmed,
                help: String(localized: "New Folder")
            ) {
                browser.createFolder(containing: selection.items.isEmpty
                    ? []
                    : browser.sidebarTree.normalized(selection.items))
                selection.clear()
            }
            .overlay {
                if newFolderDrop.isArmed {
                    Circle()
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                newFolderDrop.frame = $0
            }
        }
    }
}

struct SidebarStyleMenuItems: View {
    let sidebar: SidebarLayout

    var body: some View {
        Toggle(isOn: Binding(
            get: { sidebar.isIconsOnly },
            set: { sidebar.setIconsOnly($0) }
        )) {
            Text("Icons Only")
        }
    }
}

struct NewTabRow: View {
    let coordinator: AppCoordinator

    static let shortcutHint = "⌘T"

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false

    var body: some View {
        Button {
            coordinator.requestNewTab()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(Theme.Font.control)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                if sidebarStyle == .full {
                    Text("New Tab")
                        .font(Theme.Font.title)
                    Spacer(minLength: 0)
                    Text(verbatim: Self.shortcutHint)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .sidebarRowSelectionEffect(
                isSelected: coordinator.palette.isNewTab,
                isHovering: hovering
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(sidebarStyle == .icons ? Text("New Tab (⌘T)") : Text(verbatim: ""))
    }
}

struct SidebarDownloadsButton: View {
    let coordinator: AppCoordinator

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.chromeHoverLifts) private var hoverLifts
    @State private var hovering = false
    @State private var hoveringPreview = false
    @State private var previewing = false
    @State private var previewTask: Task<Void, Never>?
    @State private var finishPulse = 0

    private var downloads: DownloadManager {
        coordinator.browser.downloads
    }
    private var isRunning: Bool {
        downloads.activeCount > 0
    }
    private var fillFraction: CGFloat {
        0.1 + 0.8 * max(0.06, min(downloads.activeFraction, 1))
    }
    private var finishedCount: Int {
        downloads.items.count { $0.state == .finished }
    }

    var body: some View {
        Button {
            closePreview()
            coordinator.showDownloads()
        } label: {
            Image(systemName: "arrow.down")
                .font(Theme.Font.rowTitle)
                .foregroundStyle(hovering ? .primary : .secondary)
                .overlay {
                    Image(systemName: "arrow.down")
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.accent)
                        .mask(alignment: .top) {
                            GeometryReader { proxy in
                                Rectangle()
                                    .frame(height: proxy.size.height * fillFraction)
                            }
                        }
                        .opacity(isRunning ? 1 : 0)
                        .animation(Theme.Motion.drift, value: fillFraction)
                }
                .symbolEffect(.wiggle, value: finishPulse)
                .hoverLift(hoverLifts && hovering)
                .frame(width: 28, height: 28)
                .hoverBackground(isActive: !hoverLifts && hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGPoint.self) { proxy in
            CGPoint(x: proxy.frame(in: .global).midX, y: proxy.frame(in: .global).midY)
        } action: { point in
            coordinator.downloadFlights.target = point
        }
        .onHover {
            hovering = $0
            schedulePreview()
        }
        .animation(Theme.Motion.quick, value: hovering)
        .animation(Theme.Motion.settle, value: isRunning)
        .help(downloads.items.isEmpty ? helpText : Text(verbatim: ""))
        .arrowlessPopover(isPresented: $previewing) {
            DownloadsPreview(downloads: downloads) { item in
                closePreview()
                if item.state == .finished {
                    downloads.open(item)
                } else {
                    coordinator.showDownloads()
                }
            }
            .onHover {
                hoveringPreview = $0
                schedulePreview()
            }
        }
        .onChange(of: previewing) {
            if !previewing {
                hoveringPreview = false
            }
        }
        .onChange(of: finishedCount) { old, new in
            if new > old {
                finishPulse += 1
            }
        }
    }

    private var helpText: Text {
        isRunning
            ? Text("Downloads — \(downloads.activeCount) in progress")
            : Text("Downloads")
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let inside = hovering || hoveringPreview
        guard inside != previewing, !inside || !downloads.items.isEmpty else { return }
        previewTask = Task {
            try? await Task.sleep(for: inside ? .milliseconds(450) : .milliseconds(250))
            guard !Task.isCancelled else { return }
            previewing = inside
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        hoveringPreview = false
        previewing = false
    }
}

struct SidebarHistoryButton: View {
    let coordinator: AppCoordinator

    var body: some View {
        QuietIconButton(
            symbol: "clock",
            isOn: false,
            help: String(localized: "History")
        ) {
            coordinator.showHistory()
        }
    }
}

struct SidebarSettingsRow: View {
    let coordinator: AppCoordinator

    var body: some View {
        QuietIconButton(
            symbol: "gearshape",
            isOn: false,
            help: String(localized: "Settings")
        ) {
            coordinator.openSettings()
        }
    }
}
