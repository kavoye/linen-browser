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

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }
    private var showsPanel: Bool {
        panel.isVisible && coordinator.page == .browser
    }

    var body: some View {
        let width = sidebar.openWidth(in: containerWidth)
        let isExpanded = showsPanel && panel.isExpanded
        let panelWidth = isExpanded ? containerWidth : panel.openWidth(in: containerWidth)
        let panelReach = showsPanel && !isExpanded ? panelWidth : 0

        ZStack(alignment: .leading) {
            Group {
                if coordinator.page == .settings {
                    SettingsView(coordinator: coordinator)
                } else {
                    ContentArea(browser: browser, coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, sidebar.isVisible ? width : 0)
            .padding(.trailing, panelReach)

            SidePanelSurface(
                browser: browser,
                coordinator: coordinator,
                containerWidth: containerWidth
            )
            .frame(width: isExpanded ? max(containerWidth - (sidebar.isVisible ? width : 0), 0) : panelWidth)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(x: showsPanel ? 0 : panelWidth + 24)

            Sidebar(
                browser: browser,
                coordinator: coordinator,
                containerWidth: containerWidth
            )
                .frame(width: width)
                .environment(\.sidebarStyle, sidebar.style)
                .environment(\.sidebarWidth, width)
                .compositingGroup()
                .shadow(
                    color: .black.opacity(sidebar.isPeeking && !sidebar.isVisible ? 0.45 : 0),
                    radius: 22,
                    x: 6
                )
                .offset(x: sidebar.isShowing ? 0 : -(width + 24))
                .onHover { inside in
                    if !sidebar.isVisible, !inside {
                        sidebar.isPeeking = false
                    }
                }

            TabPreviewOverlay(browser: browser, model: coordinator.tabPreview)

            SidebarDragOverlay(browser: browser, model: coordinator.sidebarDrag)
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

            if coordinator.onboarding.isPresented {
                OnboardingOverlay(coordinator: coordinator, model: coordinator.onboarding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .background(Theme.windowBackground)
        .environment(\.chromeIsLight, scheme == .light)
        .animation(Theme.Motion.settle, value: sidebar.isVisible)
        .animation(nil, value: sidebar.isPeeking)
        .animation(Theme.Motion.settle, value: showsPanel)
        .animation(Theme.Motion.settle, value: panel.isExpanded)
        .animation(coordinator.isPaletteOpen ? Theme.Motion.quick : nil, value: coordinator.isPaletteOpen)
        .animation(nil, value: coordinator.onboarding.isPresented)
    }
}
