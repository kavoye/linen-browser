// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct Sidebar: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let containerWidth: CGFloat

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    @Environment(\.windowControlsInset) private var windowControlsInset
    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.colorScheme) private var scheme
    @State private var mediaObscuredHeight: CGFloat = 0
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
        VStack(alignment: sidebarStyle == .icons ? .center : .leading, spacing: 6) {
            SidebarTopRow(
                browser: browser,
                coordinator: coordinator,
                selection: selection,
                newFolderDrop: newFolderDrop
            )
            NewTabRow(coordinator: coordinator)
            ZStack(alignment: .bottom) {
                WorkspaceList(
                    browser: browser,
                    coordinator: coordinator,
                    selection: selection,
                    newFolderDrop: newFolderDrop,
                    frames: frames,
                    bottomClearance: mediaObscuredHeight
                )
                if coordinator.media.model.isActive {
                    MediaSidebarCard(
                        media: coordinator.media,
                        coordinator: coordinator,
                        obscuredHeight: $mediaObscuredHeight
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            UpdateBanner(updates: coordinator.updates)

            Group {
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
            .animation(Theme.Motion.settle, value: coordinator.browser.downloads.hasRecent)
        }
        .padding(.horizontal, sidebarStyle == .icons ? 8 : 12)
        .padding(.bottom, 12)
        .padding(.top, topPadding)
        .background {
            ZStack(alignment: .trailing) {
                Group {
                    if wearsBand {
                        ChromeBand.fill(browser: browser, coordinator: coordinator)
                    } else {
                        VisualEffectView(material: .sidebar)
                        Theme.sidebarTint.opacity(0.55)
                    }
                }
                .transaction { $0.animation = nil }

                if wearsBand {
                    ChromeBand.fill(browser: browser, coordinator: coordinator)
                        .frame(width: 1)
                        .offset(x: 1)
                        .allowsHitTesting(false)
                        .transaction { $0.animation = nil }
                }

                WindowDragArea()
                SidebarDivider(layout: sidebar, containerWidth: containerWidth)
            }
        }
        .environment(\.chromeIsLight, inkIsLight)
        .environment(\.colorScheme, inkIsLight ? .light : .dark)
        .animation(nil, value: inkIsLight)
        .animation(Theme.Motion.settle, value: coordinator.media.model.isActive)
        .onChange(of: coordinator.media.model.isActive) { _, isActive in
            if !isActive {
                mediaObscuredHeight = 0
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
    @Environment(\.windowControlsInset) private var windowControlsInset

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    private var toggleLeadingInset: CGFloat {
        guard windowControlsInset > 0 else { return 0 }
        return max(0, windowControlsInset + 1 - 12)
    }

    var body: some View {
        Group {
            if sidebarStyle == .icons {
                VStack(spacing: 2) {
                    otherButtons
                }
            } else {
                HStack(spacing: 2) {
                    sidebarToggle
                        .padding(.leading, toggleLeadingInset)
                    Spacer(minLength: 0)
                    otherButtons
                }
            }
        }
        .padding(.bottom, 2)
        .opacity(SidebarMetrics.topControlsOpacity(isShowing: sidebar.isShowing))
    }

    private var toggleHelp: LocalizedStringResource {
        sidebar.isVisible ? "Hide Sidebar" : "Pin Sidebar"
    }

    private var sidebarToggle: some View {
        QuietIconButton(
            symbol: "sidebar.left",
            isOn: false,
            help: String(localized: toggleHelp)
        ) {
            sidebar.toggleVisible()
        }
        .contextMenu {
            SidebarStyleMenuItems(sidebar: sidebar)
        }
    }

    @ViewBuilder
    private var otherButtons: some View {
        QuietIconButton(symbol: "magnifyingglass", isOn: false, help: String(localized: "Search Everything (⌘K)")) {
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
                RoundedRectangle(cornerRadius: Theme.Radius.hover)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: 28, height: 28)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFolderDrop.frame = $0 }
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
            .frame(width: 32, height: 32)
            .sidebarRowSelectionEffect(isSelected: false, isHovering: hovering)
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

    @State private var hovering = false

    var body: some View {
        Button {
            coordinator.openNewTab(url: UpdateFeed.newIssueURL)
        } label: {
            Image(systemName: "ladybug")
                .font(Theme.Font.control)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
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
                .frame(maxWidth: sidebarStyle == .full ? 32 : .infinity)
                .frame(height: 32)
                .sidebarRowSelectionEffect(isSelected: isSelected, isHovering: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("Settings"))
    }
}
