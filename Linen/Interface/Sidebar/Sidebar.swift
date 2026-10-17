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

    private var spaceEditor: SpaceEditorTarget? {
        coordinator.overlays.spaceEditor
    }

    var body: some View {
        ZStack {
            workspace
                .visualEffect { [isEditing = spaceEditor != nil && !coordinator.overlays.spaceEditorRevealsList] content, proxy in
                    content.offset(x: isEditing ? -proxy.size.width : 0)
                }
                .animation(nil, value: coordinator.overlays.spaceEditorRevealsList)
                .modifier(SpaceArrival(progress: coordinator.overlays.spaceAppearance))
                .allowsHitTesting(spaceEditor == nil)
                .clipShape(WorkspaceClip(isClipping: spaceEditor != nil || coordinator.overlays.spaceAppearance < 1))

            ZStack {
                if let spaceEditor {
                    SpaceEditor(coordinator: coordinator, target: spaceEditor)
                        .id(spaceEditor)
                        .padding(.top, topPadding)
                        .padding(.bottom, 12)
                        .modifier(SpaceEditorExit(progress: coordinator.overlays.spaceEditorExit))
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlayPreferenceValue(SpaceTipPlacement.self) { placement in
            GeometryReader { proxy in
                if let (anchor, tip) = placement {
                    let dot = proxy[anchor]
                    tip
                        .fixedSize()
                        .position(x: dot.midX, y: dot.minY - 17)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
        .background {
            ZStack {
                if let floatingGround {
                    FloatingChromeFill(shape: LoomChrome.canvasShape, ground: floatingGround)
                } else if isFloating {
                    LoomSpaceBackdrop(browser: browser, coordinator: coordinator, isFloating: true)
                }
                WindowDragArea()
                if coordinator.showsSpaces, spaceEditor == nil {
                    SpaceSwipeCatcher(onChange: swipeChanged, onEnd: swipeEnded)
                }
            }
        }
        .modifier(SidebarInk(browser: browser, coordinator: coordinator, wearsBand: wearsBand))
        .animation(Theme.Motion.settle, value: coordinator.media.model.isActive)
    }

    private func swipeChanged(_ travel: CGFloat) {
        coordinator.spaceSlider.drag(to: travel)
    }

    private func swipeEnded(_ travel: CGFloat, velocity: CGFloat) {
        coordinator.spaceSlider.endSwipe(travel: travel, velocity: velocity)
    }

    private var workspace: some View {
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

    private var showsSwitcher: Bool {
        coordinator.showsSpaces && coordinator.spaceStore.spaces.count > 1
    }

    var body: some View {
        VStack(spacing: 6) {
            SidebarPinnedCards(
                coordinator: coordinator,
                obscuredHeight: $obscuredHeight
            )

            if sidebarStyle == .icons {
                SidebarMoreMenu(coordinator: coordinator, includesSpacesAndDownloads: true)
            } else {
                HStack(spacing: 6) {
                    downloadsButton

                    if showsSwitcher {
                        SidebarSpaceSwitcher(coordinator: coordinator)
                    } else {
                        Spacer(minLength: 0)
                    }

                    SidebarMoreMenu(coordinator: coordinator)
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
    @Environment(\.sidebarHidesMediaCard) private var hidesMediaCard

    private var showsMedia: Bool {
        coordinator.media.model.isActive && !hidesMediaCard
    }

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
            if showsMedia {
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
        .onChange(of: showsMedia) { _, shows in
            if !shows {
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
    @State private var startPulse = 0

    private static let barWidth: CGFloat = 15

    private var downloads: DownloadManager {
        coordinator.browser.downloads
    }
    private var isRunning: Bool {
        downloads.activeCount > 0
    }
    private var tally: Tally {
        Tally(
            manager: ObjectIdentifier(downloads),
            active: downloads.activeCount,
            finished: downloads.items.count { $0.state == .finished }
        )
    }

    private struct Tally: Equatable {
        let manager: ObjectIdentifier
        let active: Int
        let finished: Int
    }
    var body: some View {
        Button {
            closePreview()
            coordinator.showDownloads()
        } label: {
            VStack(spacing: isRunning ? 3 : 0) {
                Image(systemName: "arrow.down")
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .symbolEffect(.bounce.down, value: startPulse)
                    .symbolEffect(.wiggle, value: finishPulse)

                Capsule()
                    .fill(Theme.Wash.strong)
                    .frame(width: Self.barWidth, height: 2)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(
                                width: Self.barWidth * max(0.06, min(downloads.activeFraction, 1)),
                                height: 2
                            )
                            .animation(Theme.Motion.drift, value: downloads.activeFraction)
                    }
                    .opacity(isRunning ? 1 : 0)
                    .frame(height: isRunning ? 2 : 0)
            }
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
        .onChange(of: tally) { old, new in
            guard old.manager == new.manager else { return }
            if new.active > old.active {
                startPulse += 1
            }
            if new.finished > old.finished {
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

private struct SidebarInk: ViewModifier {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let wearsBand: Bool

    @Environment(\.floatingGround) private var floatingGround
    @Environment(\.colorScheme) private var scheme

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
        return Sidebar.inkIsLight(browser: browser, coordinator: coordinator, scheme: scheme, wearsBand: wearsBand)
    }

    func body(content: Content) -> some View {
        let inkIsLight = inkIsLight
        return content
            .environment(\.chromeIsLight, inkIsLight)
            .environment(\.chromeWash, .of(floatingGround.map { $0.color } ?? inkColor, isLight: inkIsLight))
            .environment(\.windowColorScheme, scheme)
            .environment(\.colorScheme, inkIsLight ? .light : .dark)
            .animation(nil, value: inkIsLight)
    }
}

private struct SpaceEditorExit: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 16 * progress)
            .offset(y: -48 * progress)
            .opacity(1 - progress)
    }
}

private nonisolated struct WorkspaceClip: Shape {
    let isClipping: Bool

    func path(in rect: CGRect) -> Path {
        Path(isClipping ? rect : rect.insetBy(dx: -10_000, dy: -10_000))
    }
}

private struct SpaceArrival: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 12 * (1 - progress))
            .offset(y: 18 * (1 - progress))
    }
}
