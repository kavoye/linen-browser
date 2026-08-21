// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ContentArea: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @State private var pull = PullToRefreshMonitor()
    @State private var pullState = PullState.idle

    @Environment(\.windowControlsInset) private var windowControlsInset

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    private var showStartPage: Bool {
        ChromeBand.showsStartPage(browser: browser)
    }

    private var hidesNavBar: Bool {
        showStartPage && browser.activeSplit == nil
    }

    private var showsSteering: Bool {
        browser.activeTab?.isShowingStartPage == true
    }

    private static let barTrailingPadding: CGFloat = 10

    var body: some View {
        ZStack(alignment: .top) {
            page
                .zIndex(0)

            if hidesNavBar {
                Color.clear
                    .frame(height: Theme.topBarHeight)
                    .background { WindowDragArea() }
                    .overlay(alignment: .leading) { bareBarControls }
                    .overlay(alignment: .trailing) {
                        SidePanelToggle(coordinator: coordinator)
                            .padding(.trailing, Self.barTrailingPadding)
                    }
                    .zIndex(10)
            } else {
                ContentNavBar(browser: browser, coordinator: coordinator)
                    .zIndex(10)
            }
        }
        .onAppear {
            pull.webViewProvider = { browser.activeTab?.webView }
            pull.isCovered = { coordinator.isPaletteOpen || coordinator.onboarding.isPresented }
            pull.onChange = { state, animation in
                if let animation {
                    withAnimation(animation) { pullState = state }
                } else {
                    pullState = state
                }
            }
            pull.start()
        }
        .onDisappear {
            pull.stop()
        }
        // The bar leaves as a cut. Glass cannot fade out, and an animated removal
        // ghosts grey across the page.
        .animation(hidesNavBar ? nil : Theme.Motion.settle, value: hidesNavBar)
        .animation(Theme.Motion.settle, value: browser.activeTab?.find.isActive)
    }

    private var sidebarToggleHelp: LocalizedStringResource {
        sidebar.isVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    private var barLeadingPadding: CGFloat {
        SidebarMetrics.windowControlsPadding(
            isVisible: sidebar.isVisible,
            style: sidebar.style,
            windowControlsInset: windowControlsInset
        ) + 10
    }

    @ViewBuilder
    private var bareBarControls: some View {
        let showsToggle = SidebarTogglePlacement.inNavBar(isVisible: sidebar.isVisible, style: sidebar.style)
        if showsToggle || showsSteering {
            HStack(spacing: 6) {
                if showsToggle {
                    sidebarReveal
                }
                if showsSteering {
                    steering
                }
            }
            .padding(.leading, barLeadingPadding)
        }
    }

    private var sidebarReveal: some View {
        ToolbarButton(symbol: "sidebar.left", enabled: true, help: String(localized: sidebarToggleHelp)) {
            if sidebar.isVisible {
                sidebar.toggleVisible()
            } else {
                sidebar.show()
            }
        }
        .onHover { if $0, !sidebar.isVisible { sidebar.isPeeking = true } }
        .contextMenu {
            SidebarStyleMenuItems(sidebar: sidebar)
        }
    }

    private var steering: some View {
        HStack(spacing: 6) {
            ToolbarButton(
                symbol: "chevron.left",
                enabled: browser.activeTab?.canGoBack ?? false,
                help: String(localized: "Back"),
                heldMenu: {
                    guard let tab = browser.activeTab else { return nil }
                    return NavigationHoldMenu.back(for: tab, coordinator: coordinator)
                }
            ) {
                browser.activeTab?.goBack()
            }
            ToolbarButton(
                symbol: "chevron.right",
                enabled: browser.activeTab?.canGoForward ?? false,
                help: String(localized: "Forward"),
                heldMenu: {
                    guard let tab = browser.activeTab else { return nil }
                    return NavigationHoldMenu.forward(for: tab, coordinator: coordinator)
                }
            ) {
                browser.activeTab?.goForward()
            }
        }
    }

    private func pullBackdrop(for tab: BrowserTab) -> Color {
        tab.pageColor.map(Color.init(nsColor:))
            ?? tab.canvasColor.map(Color.init(nsColor:))
            ?? Theme.windowBackground
    }

    private var pullsAWebPage: Bool {
        guard let tab = browser.activeTab else { return false }
        return tab.internalPage == nil && !showStartPage && browser.activeSplit == nil
    }

    private var landing: SplitDropPlan.Target? {
        guard browser.activeSplit == nil, coordinator.sidebarDrag.source == .row else { return nil }
        return coordinator.sidebarDrag.target
    }

    private var page: some View {
        ZStack(alignment: .topLeading) {
            KeptAliveTabs(browser: browser, media: coordinator.media)

            Group {
                if let tab = browser.activeTab, let internalPage = tab.internalPage {
                    Group {
                        switch internalPage {
                        case .history:
                            HistoryView(browser: browser)
                        case .downloads:
                            DownloadsView(browser: browser)
                        case .releaseNotes:
                            ReleaseNotesView(browser: browser, notes: coordinator.releaseNotes)
                        }
                    }
                    .safeAreaPadding(.top, Theme.topBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let split = browser.activeSplit, let panes = browser.splitPanes {
                    SplitSurface(
                        browser: browser,
                        coordinator: coordinator,
                        split: split,
                        panes: panes,
                        pull: pullState
                    )
                    .transition(.identity)
                } else if let tab = browser.activeTab, !showStartPage {
                    ActiveWebSurface(tab: tab)
                        .transition(.identity)
                        .offset(y: pullState.offset)
                        .overlay(alignment: .top) {
                            pullBackdrop(for: tab)
                                .frame(height: Theme.topBarHeight + pullState.offset)
                                .allowsHitTesting(false)
                        }
                } else {
                    StartPage(browser: browser, coordinator: coordinator)
                        .safeAreaPadding(.top, Theme.topBarHeight)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(Theme.Motion.settle),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: browser.internalPageMoves)
            .overlay(alignment: .top) {
                if let tab = browser.activeTab, tab.isLoading {
                    LoadingBar(progress: tab.progress)
                        .padding(.top, Theme.topBarHeight + pullState.offset)
                        .transition(.opacity)
                }
            }

            if let landing {
                SplitLandingSlot(
                    outcome: .arrives,
                    topInset: landing.slot.minY == 0 ? Theme.topBarHeight : 0
                )
                .frame(width: landing.slot.width, height: landing.slot.height)
                .offset(x: landing.slot.minX, y: landing.slot.minY)
                .animation(Theme.Motion.quick, value: landing)
                .zIndex(6)
            }

            if let tab = browser.activeTab, tab.find.isActive {
                HStack {
                    Spacer()
                    FindBar(session: tab.find)
                }
                .id(tab.id)
                .padding(.top, Theme.topBarHeight + 10)
                .padding(.trailing, 14)
                .zIndex(5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if pullsAWebPage {
                PullIndicator(state: pullState)
                    .frame(maxWidth: .infinity)
                    .offset(y: Theme.topBarHeight + pullState.offset / 2 - PullIndicator.size / 2)
                    .zIndex(4)
                    .allowsHitTesting(false)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            coordinator.sidebarDrag.contentFrameInWindow = frame
        }
        .animation(Theme.Motion.settle, value: browser.activeTab?.isLoading)
    }
}

private struct KeptAliveTabs: View {
    let browser: BrowserModel
    let media: MediaCenter

    var body: some View {
        let kept = browser.tabs.filter { tab in
            tab.id != browser.activeTab?.id
                && !browser.isVisibleInSplit(tab)
                && tab.internalPage == nil
                && tab.webView !== media.model.pictureWebView
                && (tab.isPlayingAudio || media.controlledTabID == tab.id)
        }
        ForEach(kept) { tab in
            WebViewRepresentable(webView: tab.webView, parksWhenIdle: true)
                .id(tab.id)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

private struct ActiveWebSurface: View {
    let tab: BrowserTab

    var body: some View {
        WebViewRepresentable(webView: tab.webView, parksWhenIdle: true)
            .id(tab.id)
            .background(
                tab.canvasColor.map(Color.init(nsColor:)) ?? Theme.windowBackground
            )
            .overlay {
                if !tab.hasPresentedContent {
                    Theme.windowBackground
                        .transition(.identity)
                }
            }
    }
}

struct LoadingBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.accent)
                .frame(width: max(24, proxy.size.width * progress), height: 2.5)
                .animation(Theme.Motion.drift, value: progress)
        }
        .frame(height: 2.5)
        .allowsHitTesting(false)
    }
}
