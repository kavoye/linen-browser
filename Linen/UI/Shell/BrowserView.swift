// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct BrowserView: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @State private var settingsWorkspace: SettingsWorkspace

    init(browser: BrowserModel, coordinator: AppCoordinator) {
        self.browser = browser
        self.coordinator = coordinator
        let workspace = SettingsWorkspace(coordinator: coordinator)
        workspace.onRoute = { [weak coordinator] category in
            coordinator?.routeSettings(to: category)
        }
        _settingsWorkspace = State(initialValue: workspace)
    }

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
                settingsWorkspace: settingsWorkspace,
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
                sidebarEdge: sidebar.isShowing ? width : 0
            )

            SidebarDragOverlay(browser: browser, model: coordinator.sidebarDrag)

            DownloadFlightLayer(flights: coordinator.downloadFlights)
                .environment(\.sidebarStyle, sidebar.style)

            PaneDragOverlay(browser: browser, model: coordinator.sidebarDrag)

            if !sidebar.isShowing {
                Color.clear
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { sidebar.isPeeking = true } }
            }

            if coordinator.isPaletteOpen {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.35)
                            .contentShape(Rectangle())
                            .onTapGesture { coordinator.closePalette() }

                        CommandPalette(
                            browser: browser,
                            coordinator: coordinator,
                            containerSize: proxy.size
                        ) {
                            coordinator.closePalette()
                        }
                        .id(coordinator.paletteToken)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .transition(.opacity)
            }

            if coordinator.isProfileSwitcherOpen, let anchor = coordinator.profileButtonFrame {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { coordinator.isProfileSwitcherOpen = false }

                        ProfileSwitcher(coordinator: coordinator) {
                            coordinator.isProfileSwitcherOpen = false
                        }
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
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            containerWidth = $0
        }
        .background(Color.clear)
        .environment(\.chromeIsLight, scheme == .light)
        .environment(\.chromeWash, .of(nil, isLight: scheme == .light))
        .animation(chromeMotion, value: sidebar.isVisible)
        .animation(nil, value: sidebar.isPeeking)
        .animation(chromeMotion, value: showsPanel)
        .animation(chromeMotion, value: panel.isExpanded)
        .animation(
            coordinator.isPaletteOpen ? Theme.Motion.quick : nil, value: coordinator.isPaletteOpen
        )
        .animation(
            coordinator.isProfileSwitcherOpen ? Theme.Motion.quick : nil,
            value: coordinator.isProfileSwitcherOpen
        )

        .animation(nil, value: coordinator.onboarding.isPresented)
    }
}
