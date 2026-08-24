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
    @Environment(\.colorScheme) private var scheme
    @State private var bottomObscuredHeight: CGFloat = 0
    @State private var newFolderDrop = SidebarNewFolderDrop()

    private var selection: SidebarSelection {
        browser.sidebarSelection
    }

    private var frames: SidebarFrames {
        coordinator.sidebarDrag.frames
    }

    private var wearsBand: Bool {
        sidebarStyle == .icons
    }

    private var inkIsLight: Bool {
        if coordinator.page == .browser {
            return PageInk.isLight(
                LoomChrome.sampledColor(
                    ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
                    scheme: scheme
                ),
                scheme: scheme
            )
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
        guard sidebarStyle == .full else {
            return EdgeInsets(top: 0, leading: LoomChrome.canvasInset, bottom: 0, trailing: 0)
        }
        let inset = SidebarMetrics.contentInset(style: .full)
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
            frames: frames,
            bottomClearance: bottomObscuredHeight,
            topBar: SidebarTopChrome(
                browser: browser,
                coordinator: coordinator,
                selection: selection,
                newFolderDrop: newFolderDrop
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
                if sidebar.isFloating {
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

    var body: some View {
        VStack(spacing: 6) {
            SidebarTopRow(
                browser: browser,
                coordinator: coordinator,
                selection: selection,
                newFolderDrop: newFolderDrop
            )
            NewTabRow(coordinator: coordinator)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SidebarBottomChrome: View {
    let coordinator: AppCoordinator
    @Binding var obscuredHeight: CGFloat

    @Environment(\.sidebarStyle) private var sidebarStyle

    private var expandsProfile: Bool {
        sidebarStyle == .full
    }

    @ViewBuilder private var downloadsButton: some View {
        if coordinator.browser.downloads.hasRecent {
            SidebarDownloadsButton(coordinator: coordinator)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            SidebarPinnedCards(
                coordinator: coordinator,
                obscuredHeight: $obscuredHeight
            )

            if sidebarStyle == .icons {
                VStack(spacing: 6) {
                    SidebarProfileButton(coordinator: coordinator)
                    downloadsButton
                    if coordinator.settings.showsReportIssueButton {
                        SidebarFeedbackRow(coordinator: coordinator)
                    }
                    SidebarSettingsRow(coordinator: coordinator)
                }
            } else {
                HStack(spacing: 6) {
                    if expandsProfile {
                        SidebarProfileButton(coordinator: coordinator)
                        downloadsButton
                        if coordinator.settings.showsReportIssueButton {
                            SidebarFeedbackRow(coordinator: coordinator)
                        }
                        SidebarSettingsRow(coordinator: coordinator)
                    } else {
                        SidebarSettingsRow(coordinator: coordinator)
                        if coordinator.settings.showsReportIssueButton {
                            SidebarFeedbackRow(coordinator: coordinator)
                        }
                        downloadsButton
                        SidebarProfileButton(coordinator: coordinator)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.settle, value: coordinator.browser.downloads.hasRecent)
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
        .opacity(SidebarMetrics.topControlsOpacity(isShowing: sidebar.isShowing))
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

    private var barIsLight: Bool {
        PageInk.isLight(
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
            Text("Use Icons Only")
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
            coordinator.openNewTab()
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
            .padding(.horizontal, sidebarStyle == .icons ? 0 : 9)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .sidebarRowSelectionEffect(isSelected: false, isHovering: hovering)
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
    @State private var hovering = false

    private var downloads: DownloadManager {
        coordinator.browser.downloads
    }
    private var isShowingDownloads: Bool {
        guard case .tab(let id) = coordinator.sidebarDestination else { return false }
        return coordinator.browser.tab(id: id)?.internalPage == .downloads
    }

    var body: some View {
        Button {
            coordinator.showDownloads()
        } label: {
            ZStack {
                if downloads.activeCount > 0 {
                    Circle()
                        .stroke(Theme.Wash.selection, lineWidth: 2)
                        .frame(width: 19, height: 19)
                    Circle()
                        .trim(from: 0, to: max(0.05, downloads.activeFraction))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 19, height: 19)
                        .animation(Theme.Motion.drift, value: downloads.activeFraction)
                }

                Image(systemName: "arrow.down")
                    .font(.system(size: downloads.activeCount > 0 ? 9 : 12, weight: .medium))
                    .foregroundStyle(isShowingDownloads ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: SidebarMetrics.controlMaxWidth(style: sidebarStyle))
            .frame(height: SidebarMetrics.controlHeight)
            .sidebarRowSelectionEffect(isSelected: isShowingDownloads, isHovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(downloads.activeCount > 0
              ? Text("Downloads — \(downloads.activeCount) in progress")
              : Text("Downloads"))
    }
}

struct SidebarFeedbackRow: View {
    let coordinator: AppCoordinator

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false

    var body: some View {
        Button {
            coordinator.openNewTab(url: UpdateFeed.newIssueURL)
        } label: {
            Image(systemName: "ladybug")
                .font(Theme.Font.control)
                .foregroundStyle(.secondary)
                .frame(maxWidth: SidebarMetrics.controlMaxWidth(style: sidebarStyle))
                .frame(height: SidebarMetrics.controlHeight)
                .sidebarRowSelectionEffect(isSelected: false, isHovering: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("Report an issue"))
    }
}

struct SidebarSettingsRow: View {
    let coordinator: AppCoordinator

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false

    private var isSelected: Bool {
        coordinator.sidebarDestination == .settings
    }

    var body: some View {
        Button {
            coordinator.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(Theme.Font.control)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(maxWidth: SidebarMetrics.controlMaxWidth(style: sidebarStyle))
                .frame(height: SidebarMetrics.controlHeight)
                .sidebarRowSelectionEffect(isSelected: isSelected, isHovering: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("Settings"))
    }
}
