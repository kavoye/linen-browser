// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct BrowserView: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }
    @State private var containerWidth: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    private var chromeSitsOnALightPage: Bool {
        PageInk.isLight(
            ChromeBand.pageColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
    }

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }
    private var showsPanel: Bool {
        panel.isVisible
    }

    private var chromeMotion: Animation? {
        coordinator.isSwitchingProfile ? nil : Theme.Motion.settle
    }

    var body: some View {
        let loom = ChromeBand.loomWash(browser: browser, coordinator: coordinator, scheme: scheme)
        let loomScheme: ColorScheme = loom.isLight ? .light : .dark
        let width = sidebar.openWidth(in: containerWidth)
        let roomBesideSidebar = containerWidth - (sidebar.isVisible ? width : 0)
        let isExpanded = showsPanel && panel.isExpanded
        let shell = LoomShellGeometry(
            containerWidth: containerWidth,
            sidebarWidth: width,
            preferredPanelWidth: panel.openWidth(in: roomBesideSidebar),
            isSidebarVisible: sidebar.isVisible,
            isPanelVisible: showsPanel,
            isPanelExpanded: isExpanded
        )

        ZStack(alignment: .leading) {
            LoomAmbientBackdrop(
                sampledPageColor: ChromeBand.pageColor(
                    browser: browser,
                    coordinator: coordinator
                ),
                settings: coordinator.settings
            )

            ContentArea(
                browser: browser,
                coordinator: coordinator,
                settingsWorkspace: coordinator.settingsWorkspace,
                canvasTrailingInset: shell.canvasTrailingInset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, sidebar.isVisible ? width : 0)

            SidePanelSurface(
                browser: browser,
                coordinator: coordinator
            )
            .frame(width: shell.panelWidth)
            .padding(.top, LoomChrome.canvasTop)
            .padding(.trailing, LoomChrome.canvasInset)
            .padding(.bottom, LoomChrome.canvasInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(x: showsPanel ? 0 : shell.panelWidth + LoomChrome.canvasInset + 24)

            if showsPanel && !isExpanded {
                LoomColumnResizeHandle(
                    grabWidth: LoomChrome.resizeGrabWidth,
                    onLightPage: chromeSitsOnALightPage,
                    isDragging: panel.isDragging,
                    onDragChanged: {
                        panel.dragChanged(translation: $0, available: roomBesideSidebar)
                    },
                    onDragEnded: {
                        panel.dragEnded(translation: $0, available: roomBesideSidebar)
                    },
                    onReset: { panel.resetWidth() }
                )
                .padding(.top, LoomChrome.canvasTop)
                .padding(.bottom, LoomChrome.canvasInset)
                .offset(x: shell.panelResizeLeading)
            }

            ContentNavBar(browser: browser, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.leading, sidebar.isVisible ? width : 0)

            Sidebar(
                browser: browser,
                coordinator: coordinator
            )
            .frame(width: width)
            .environment(\.sidebarStyle, sidebar.style)
            .environment(\.sidebarWidth, width)
            .environment(\.sidebarIsFloating, sidebar.isFloating)
            .compositingGroup()
            .shadow(
                color: .black.opacity(sidebar.isFloating ? 0.45 : 0),
                radius: 22,
                x: 6
            )
            .offset(x: sidebar.isShowing ? 0 : -(width + 24))
            .onHover { inside in
                if !sidebar.isVisible, !inside {
                    sidebar.isPeeking = false
                }
            }

            if sidebar.isShowing {
                LoomColumnResizeHandle(
                    grabWidth: LoomChrome.resizeGrabWidth,
                    onLightPage: chromeSitsOnALightPage,
                    isDragging: sidebar.isDragging,
                    onDragChanged: {
                        sidebar.dragChanged(translation: $0, container: containerWidth)
                    },
                    onDragEnded: {
                        sidebar.dragEnded(translation: $0, container: containerWidth)
                    },
                    onReset: { sidebar.resetWidth() }
                )
                .padding(.top, LoomChrome.canvasTop)
                .padding(.bottom, LoomChrome.canvasInset)
                .offset(
                    x: shell.sidebarResizeLeading
                )
            }

            SidebarVisibilityToggle(browser: browser, coordinator: coordinator)

            TabPreviewOverlay(
                browser: browser,
                model: coordinator.tabPreview,
                sidebarEdge: sidebar.isShowing ? width : 0,
                github: coordinator.settings.showsGitHub && coordinator.github.canPreview ? coordinator.github : nil
            )
            .environment(\.colorScheme, loomScheme)

            GitHubPreviewOverlay(presenter: coordinator.githubPreview, model: coordinator.github)
                .environment(\.colorScheme, loomScheme)

            SidebarDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .environment(\.windowColorScheme, loomScheme)
                .environment(\.sidebarStyle, sidebar.style)

            DownloadFlightLayer(flights: coordinator.downloadFlights)
                .environment(\.sidebarStyle, sidebar.style)

            PaneDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .environment(\.windowColorScheme, loomScheme)

            if browser.isSwitchingTabs {
                TabSwitcherOverlay(browser: browser)
                    .environment(\.colorScheme, loomScheme)
            }

            if !sidebar.isShowing {
                Color.clear
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { sidebar.isPeeking = true } }
            }

            if coordinator.isPaletteOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closePalette() }
            }

            CommandPaletteLayer(browser: browser, coordinator: coordinator)
                .environment(\.chromeIsLight, loom.isLight)
                .environment(\.chromeWash, loom)
                .environment(\.colorScheme, loomScheme)

            if coordinator.isProfileSwitcherOpen, let anchor = coordinator.profileButtonFrame {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { coordinator.isProfileSwitcherOpen = false }

                        ProfileSwitcher(coordinator: coordinator) {
                            coordinator.isProfileSwitcherOpen = false
                        }
                        .environment(\.chromeIsLight, loom.isLight)
                        .environment(\.chromeWash, loom)
                        .environment(\.colorScheme, loomScheme)
                        .padding(.leading, anchor.minX)
                        .padding(.bottom, max(0, proxy.size.height - anchor.minY + 6))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .transition(.opacity)
            }

            if coordinator.onboarding.isPresented {
                OnboardingOverlay(coordinator: coordinator, model: coordinator.onboarding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            containerWidth = frame.width
            coordinator.noteShellFrame(frame)
        }
        .background(Color.clear)
        .onChange(of: ObjectIdentifier(browser.context)) { _, _ in
            coordinator.settingsWorkspace.adoptProfile(coordinator: coordinator)
        }
        .modifier(TranslationDownloadHost(downloads: coordinator.translationDownloads))
        .environment(\.chromeIsLight, scheme == .light)
        .environment(\.chromeWash, .of(nil, isLight: scheme == .light))
        .animation(chromeMotion, value: sidebar.isVisible)
        .animation(nil, value: sidebar.isPeeking)
        .animation(chromeMotion, value: showsPanel)
        .animation(chromeMotion, value: panel.isExpanded)
        .animation(
            coordinator.isPaletteOpen ? Theme.Motion.settle : nil,
            value: coordinator.isPaletteOpen
        )
        .animation(
            coordinator.isProfileSwitcherOpen ? Theme.Motion.quick : nil,
            value: coordinator.isProfileSwitcherOpen
        )

        .animation(nil, value: coordinator.onboarding.isPresented)
    }
}

private struct CommandPaletteLayer: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @State private var model: CommandPaletteModel?
    @State private var isShown = false
    @State private var isLeaving = false
    @State private var isMoving = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let layout = CommandPaletteLayout(containerSize: proxy.size)
            let anchor = UnitPoint(
                x: 0.5,
                y: (layout.topInset + CommandPaletteLayout.fieldHeight / 2) / max(proxy.size.height, 1)
            )
            ZStack(alignment: .top) {
                if isShown, let model {
                    CommandPalette(model: model, containerSize: proxy.size)
                        .id(coordinator.paletteToken)
                        .environment(\.paletteIsMoving, isMoving)
                        .environment(\.paletteIsLeaving, isLeaving)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .scaleEffect(isLeaving ? 0.97 : 1, anchor: anchor)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.94, anchor: anchor).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
        }
        .onAppear { follow(coordinator.isPaletteOpen) }
        .onChange(of: coordinator.isPaletteOpen) { _, isOpen in follow(isOpen) }
    }

    private func follow(_ isOpen: Bool) {
        pending?.cancel()
        isMoving = true
        if isOpen {
            let coordinator = coordinator
            model = CommandPaletteModel(browser: browser, coordinator: coordinator) {
                coordinator.closePalette()
            }
            isLeaving = false
            withAnimation(.spring(duration: 0.28, bounce: 0.18)) { isShown = true }
            pending = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isMoving = false
            }
        } else if isShown {
            withAnimation(.easeOut(duration: 0.16)) { isLeaving = true }
            pending = Task {
                try? await Task.sleep(for: .milliseconds(170))
                guard !Task.isCancelled else { return }
                var cut = Transaction()
                cut.disablesAnimations = true
                withTransaction(cut) {
                    isShown = false
                    isLeaving = false
                }
                model = nil
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var paletteIsMoving = false
    @Entry var paletteIsLeaving = false
}
