// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct ContentArea: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let settingsWorkspace: SettingsWorkspace
    let canvasTrailingInset: CGFloat

    @State private var pull = PullToRefreshMonitor()
    @State private var pullState = PullState.idle

    private var showStartPage: Bool {
        ChromeBand.showsStartPage(browser: browser)
    }

    private var showsPagePanelFill: Bool {
        if let panes = browser.splitPanes {
            return panes.allSatisfy { ChromeBand.showsStartPage(for: $0) }
        }
        return showStartPage || browser.activeTab?.internalPage != nil
    }

    var body: some View {
        LoomPageCanvas(
            trailingInset: canvasTrailingInset,
            showsPanelFill: showsPagePanelFill
        ) {
            page
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
        .animation(Theme.Motion.settle, value: browser.activeTab?.find.isActive)
    }

    private var pullsAWebPage: Bool {
        guard !coordinator.isShowingSettings else { return false }
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
                if let split = browser.activeSplit, let panes = browser.splitPanes {
                    SplitSurface(
                        browser: browser,
                        coordinator: coordinator,
                        settingsWorkspace: settingsWorkspace,
                        split: split,
                        panes: panes,
                        pull: pullState
                    )
                    .transition(.identity)
                } else if let tab = browser.activeTab, let internalPage = tab.internalPage {
                    InternalPageSurface(
                        page: internalPage,
                        browser: browser,
                        coordinator: coordinator,
                        settingsWorkspace: settingsWorkspace
                    )
                    .transition(.identity)
                } else if let tab = browser.activeTab, !showStartPage {
                    ActiveWebSurface(tab: tab)
                        .transition(.identity)
                        .offset(y: pullState.offset)
                        .overlay(alignment: .top) {
                            tab.surfaceColor
                                .frame(height: pullState.offset)
                                .allowsHitTesting(false)
                        }
                } else {
                    StartPage(browser: browser, coordinator: coordinator)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(Theme.Motion.settle),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .overlay(alignment: .top) {
                if !coordinator.isShowingSettings, let tab = browser.activeTab, tab.isLoading {
                    LoadingBar(progress: tab.progress)
                        .padding(.top, pullState.offset)
                        .transition(.opacity)
                }
            }

            if let landing {
                SplitLandingSlot(
                    outcome: .arrives,
                    topInset: 0
                )
                .frame(width: landing.slot.width, height: landing.slot.height)
                .offset(x: landing.slot.minX, y: landing.slot.minY)
                .animation(Theme.Motion.quick, value: landing)
                .zIndex(6)
            }

            if !coordinator.isShowingSettings, let tab = browser.activeTab, tab.find.isActive {
                HStack {
                    Spacer()
                    FindBar(session: tab.find)
                }
                .id(tab.id)
                .padding(.top, 10)
                .padding(.trailing, 14)
                .zIndex(5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if pullsAWebPage {
                PullIndicator(state: pullState)
                    .frame(maxWidth: .infinity)
                    .offset(y: pullState.offset / 2 - PullIndicator.size / 2)
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
            tab.isMaterialised
                && tab.id != browser.activeTab?.id
                && !browser.isVisibleInSplit(tab)
                && tab.internalPage == nil
                && (tab.isPlayingAudio || media.controlledTabID == tab.id)
                && tab.webView !== media.model.pictureWebView
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
        WebViewRepresentable(
            webView: tab.webView,
            parksWhenIdle: true,
            onReady: { tab.webViewDidBecomeVisible() }
        )
            .id(tab.id)
            .background(tab.surfaceColor)
            .overlay {
                if !tab.hasPresentedContent {
                    Theme.windowBackground
                        .transition(.identity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                LinkPreview(address: tab.hoveredLink?.absoluteString)
            }
    }
}

struct LoadingBar: View {
    let progress: Double

    private static let thickness: CGFloat = 2
    private static let minimumWidth: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(progress, 0), 1)
            let width = min(
                proxy.size.width,
                max(Self.minimumWidth, proxy.size.width * fraction)
            )
            Capsule()
                .fill(Theme.accent)
                .frame(width: width, height: Self.thickness)
                .animation(Theme.Motion.drift, value: progress)
        }
        .frame(height: Self.thickness)
        .allowsHitTesting(false)
    }
}
