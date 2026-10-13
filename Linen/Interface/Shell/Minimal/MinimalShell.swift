// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MinimalShell: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let isLeaving: Bool

    init(browser: BrowserModel, coordinator: AppCoordinator, arrives: Bool = false, isLeaving: Bool = false) {
        self.browser = browser
        self.coordinator = coordinator
        self.isLeaving = isLeaving
        _hasArrived = State(initialValue: !arrives)
        _barEdge = State(initialValue: coordinator.settings.minimalBarEdge)
    }

    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var tabButtonFrame: CGRect = .zero
    @State private var isIslandRaised = true
    @State private var hasArrived: Bool
    @State private var barEdge: MinimalBarEdge
    @State private var islandWidth: CGFloat = 0
    @State private var mediaHeight: CGFloat = 0
    @State private var isTabListPeeking = false
    @State private var hasEnteredTabList = false
    @State private var tabListFrame: CGRect = .zero
    @State private var isTabListMounted = false
    @State private var isTabListIn = false
    @Environment(\.colorScheme) private var scheme

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    private static let islandClearance: CGFloat = 12
    nonisolated static let space = "minimalShell"
    static let islandMotion = Animation.spring(duration: 0.32, bounce: 0.12)

    private var floating: FloatingGround {
        if browser.activeTab?.isPrivate == true {
            return FloatingGround(nil, scheme: .dark)
        }
        return FloatingGround(IslandBar.ground(for: browser.activeTab), scheme: scheme)
    }

    private var chromeIsBusy: Bool {
        coordinator.state == .listening
            || coordinator.statusMessage != nil
            || coordinator.agentReply.message(inSpace: browser.activeSpaceID) != nil
            || coordinator.pendingAgentQuestion(inChrome: true) != nil
    }

    private var barOnTop: Bool {
        barEdge == .top
    }
    private static let mediaCardWidth: CGFloat = 280
    private static let cornerInset: CGFloat = 14

    private var islandDrop: CGFloat {
        (barOnTop ? -1 : 1) * (IslandBar.height + IslandBar.edgeGap + 24)
    }

    private var panelRoom: CGFloat {
        let beside = (containerWidth - islandWidth) / 2 - Self.islandClearance - LoomChrome.canvasInset
        return beside + SidePanelMetrics.pageMinWidth
    }

    var body: some View {
        let loom = ChromeBand.loomWash(browser: browser, coordinator: coordinator, scheme: scheme)
        let showsPanel = panel.isVisible
        let shell = LoomShellGeometry(
            containerWidth: containerWidth,
            sidebarWidth: 0,
            preferredPanelWidth: panel.openWidth(in: panelRoom),
            isSidebarVisible: false,
            isPanelVisible: showsPanel,
            isPanelExpanded: showsPanel && panel.isExpanded
        )

        ZStack(alignment: .leading) {
            MinimalShellSensor(
                onScroll: { towardTop in
                    guard coordinator.settings.hidesMinimalBar,
                          !chromeIsBusy,
                          !coordinator.overlays.isPointerOnPageCover,
                          !coordinator.overlays.isTabListOpen
                    else { return }
                    raiseIsland(towardTop)
                },
                onEdge: { edge in
                    if edge == coordinator.settings.minimalBarEdge {
                        raiseIsland(true)
                    }
                },
                onPointerDown: { point in closePanels(unlessAt: point) },
                pinsWindowControls: coordinator.overlays.isTabListOpen
            )
            .allowsHitTesting(false)

            IslandBar(
                browser: browser,
                coordinator: coordinator,
                floating: floating,
                width: IslandBar.width(
                    fullAddress: coordinator.settings.showsFullAddress,
                    available: containerWidth - 2 * Self.cornerInset
                ),
                onTabButtonFrame: { tabButtonFrame = $0 }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { islandWidth = $0 }
            .padding(barOnTop ? .top : .bottom, IslandBar.edgeGap)
            .offset(y: isIslandRaised && hasArrived ? 0 : islandDrop)
            .visualEffect { [drop = isLeaving ? islandDrop : 0] content, _ in content.offset(y: drop) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barOnTop ? .top : .bottom)

            if coordinator.media.model.isActive, !isTabListMounted {
                MediaSidebarCard(
                    media: coordinator.media,
                    coordinator: coordinator,
                    obscuredHeight: $mediaHeight
                )
                .environment(\.sidebarStyle, .full)
                .environment(\.sidebarWidth, Self.mediaCardWidth)
                .environment(\.sidebarIsFloating, true)
                .environment(\.floatingGround, floating)
                .environment(\.colorScheme, floating.isLight ? .light : .dark)
                .fixedSize()
                .shieldsPage(.mediaCard, coordinator: coordinator)
                .padding(.leading, Self.cornerInset)
                .padding(.bottom, IslandBar.edgeGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom)
                ))
            }

            SidePanelSurface(browser: browser, coordinator: coordinator)
                .environment(\.floatingGround, floating)
                .shieldsPage(.sidePanel, coordinator: coordinator)
                .frame(width: shell.panelWidth)
                .shadow(color: .black.opacity(showsPanel ? 0.28 : 0), radius: 22, x: -6)
                .padding(LoomChrome.canvasInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: showsPanel ? 0 : shell.panelWidth + LoomChrome.canvasInset + 24)

            if showsPanel && !panel.isExpanded {
                LoomColumnResizeHandle(
                    grabWidth: LoomChrome.resizeGrabWidth,
                    onLightPage: loom.isLight,
                    isDragging: panel.isDragging,
                    onDragChanged: { panel.dragChanged(translation: $0, available: panelRoom) },
                    onDragEnded: { panel.dragEnded(translation: $0, available: panelRoom) },
                    onReset: { panel.resetWidth() }
                )
                .padding(.vertical, LoomChrome.canvasInset)
                .offset(x: shell.panelResizeLeading)
            }

            WindowDragArea()
                .frame(height: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if coordinator.pendingAgentQuestion(inChrome: true) != nil {
                questionPanel
            }

            if isTabListMounted {
                tabList
            }

            if !coordinator.overlays.isTabListOpen {
                Color.clear
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside else { return }
                        isTabListPeeking = true
                        coordinator.overlays.isTabListOpen = true
                    }
            }

            SidebarDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .environment(\.windowColorScheme, floating.isLight ? .light : .dark)
                .environment(\.sidebarStyle, coordinator.sidebar.style)

            PaneDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .environment(\.windowColorScheme, floating.isLight ? .light : .dark)

            if let tab = browser.activeTab, browser.activeSplit == nil, !coordinator.isShowingSettings {
                LinkPreview(
                    address: tab.hoveredLink?.absoluteString,
                    intent: .of(coordinator.linkModifiers),
                    ground: tab.canvasColor
                )
                .padding(.bottom, coordinator.media.model.isActive ? mediaHeight + IslandBar.edgeGap : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            ProfileSwitcherLayer(coordinator: coordinator)
                .environment(\.chromeIsLight, floating.isLight)
                .environment(\.chromeWash, .of(floating.color, isLight: floating.isLight))
                .environment(\.colorScheme, floating.isLight ? .light : .dark)

            if browser.isSwitchingTabs {
                TabSwitcherOverlay(
                    browser: browser,
                    onClose: { coordinator.closeAskingIfPinned($0) },
                    onToggleMute: { coordinator.toggleMute(tab: $0) }
                )
                .environment(\.floatingGround, floating)
                .environment(\.colorScheme, floating.isLight ? .light : .dark)
            }

            if coordinator.palette.isOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closePalette() }
            }

            CommandPaletteLayer(browser: browser, coordinator: coordinator)
                .environment(\.floatingGround, floating)
                .environment(\.chromeIsLight, floating.isLight)
                .environment(\.chromeWash, .of(floating.color, isLight: floating.isLight))
                .environment(\.colorScheme, floating.isLight ? .light : .dark)
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            containerWidth = $0.width
            containerHeight = $0.height
        }
        .animation(Theme.Motion.settle, value: coordinator.media.model.isActive)
        .onChange(of: coordinator.media.model.isActive) { _, isActive in
            if !isActive {
                coordinator.overlays.notePointer(on: .mediaCard, false)
            }
        }
        .onChange(of: panel.isVisible) { _, isVisible in
            if !isVisible {
                coordinator.overlays.notePointer(on: .sidePanel, false)
            }
        }
        .animation(
            coordinator.overlays.isProfileSwitcherOpen ? Theme.Motion.quick : nil,
            value: coordinator.overlays.isProfileSwitcherOpen
        )
        .onAppear {
            guard !hasArrived else { return }
            withAnimation(Self.islandMotion) { hasArrived = true }
        }
        .onChange(of: browser.activeTab?.id) { old, _ in
            raiseIsland(true)
            if browser.tabs.contains(where: { $0.id == old }) {
                coordinator.overlays.isTabListOpen = false
            }
        }
        .onChange(of: coordinator.palette.isOpen) { _, isOpen in
            if isOpen {
                coordinator.overlays.isTabListOpen = false
            }
        }
        .onChange(of: coordinator.overlays.isTabListOpen) { _, isOpen in
            slideTabList(in: isOpen)
            if !isOpen {
                isTabListPeeking = false
                hasEnteredTabList = false
                coordinator.overlays.notePointer(on: .tabList, false)
            }
        }
        .onChange(of: browser.activeTab?.urlString) { _, _ in raiseIsland(true) }
        .onChange(of: coordinator.settings.hidesMinimalBar) { _, hides in
            if !hides {
                raiseIsland(true)
            }
        }
        .onChange(of: coordinator.settings.minimalBarEdge) { _, _ in
            withAnimation(Self.islandMotion) {
                isIslandRaised = false
            } completion: {
                barEdge = coordinator.settings.minimalBarEdge
                raiseIsland(true)
            }
        }
        .onChange(of: chromeIsBusy) { _, busy in
            if busy {
                raiseIsland(true)
            }
        }
        .onChange(of: coordinator.notice.text) { _, notice in
            if notice != nil {
                raiseIsland(true)
            }
        }
    }

    private var tabListWidth: CGFloat {
        coordinator.sidebar.openWidth(in: containerWidth)
    }

    private func closePanels(unlessAt windowPoint: CGPoint) {
        let point = CGPoint(x: windowPoint.x, y: containerHeight - windowPoint.y)
        if coordinator.overlays.isTabListOpen, point.x > tabListWidth + 2 * LoomChrome.canvasInset, !tabButtonFrame.contains(point) {
            coordinator.overlays.isTabListOpen = false
        }
    }

    private var questionPanel: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return AskQuestionBlock(questions: coordinator.agentQuestions, placement: .toolbar)
            .padding(.vertical, 6)
            .frame(width: min(max(islandWidth, 360), 560))
            .background { FloatingChromeFill(shape: shape, ground: floating) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(floating.ink.opacity(0.1), lineWidth: 0.5) }
            .shadow(color: .black.opacity(floating.isLight ? 0.14 : 0.32), radius: 18, y: 6)
            .environment(\.chromeIsLight, floating.isLight)
            .environment(\.chromeWash, .of(floating.color, isLight: floating.isLight))
            .environment(\.colorScheme, floating.isLight ? .light : .dark)
            .shieldsPage(.question, coordinator: coordinator)
            .padding(barOnTop ? .top : .bottom, IslandBar.edgeGap + IslandBar.height + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: barOnTop ? .top : .bottom)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.96, anchor: barOnTop ? .top : .bottom).combined(with: .opacity),
                removal: .identity
            ))
    }

    private var tabList: some View {
        let sidebar = coordinator.sidebar
        let shape = LoomChrome.canvasShape
        return Sidebar(browser: browser, coordinator: coordinator)
            .environment(\.sidebarStyle, sidebar.style)
            .environment(\.sidebarWidth, tabListWidth)
            .environment(\.sidebarIsFloating, true)
            .environment(\.floatingGround, floating)
            .contentShape(shape)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .frame(width: tabListWidth)
            .shadow(color: .black.opacity(0.28), radius: 22, x: 6)
            .padding(LoomChrome.canvasInset)
            .contentShape(Rectangle())
            .shieldsPage(.tabList, coordinator: coordinator)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                tabListFrame = $0
            }
            .onHover { inside in
                if inside {
                    hasEnteredTabList = true
                } else {
                    closePeekedTabListUnlessPointerOnIt()
                }
            }
            .onChange(of: coordinator.overlays.isProfileSwitcherOpen) { _, isOpen in
                if !isOpen {
                    closePeekedTabListUnlessPointerOnIt()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                closePeekedTabListUnlessPointerOnIt()
            }
            .offset(x: isTabListIn ? 0 : -(tabListWidth + 2 * LoomChrome.canvasInset + 24))
            .transition(.asymmetric(insertion: .move(edge: .leading), removal: .identity))
    }

    private func closePeekedTabListUnlessPointerOnIt() {
        guard isTabListPeeking, hasEnteredTabList, !coordinator.overlays.isProfileSwitcherOpen else { return }
        if let pointer = coordinator.pointerInShell, tabListFrame.contains(pointer) {
            return
        }
        coordinator.overlays.isTabListOpen = false
    }

    private func slideTabList(in isOpen: Bool) {
        if isTabListPeeking {
            isTabListIn = isOpen
            isTabListMounted = isOpen
            return
        }
        guard isOpen else {
            withAnimation(Theme.Motion.settle) {
                isTabListIn = false
            } completion: {
                if !coordinator.overlays.isTabListOpen {
                    isTabListMounted = false
                }
            }
            return
        }
        withAnimation(Theme.Motion.settle) {
            isTabListMounted = true
            isTabListIn = true
        }
    }

    private func raiseIsland(_ raised: Bool) {
        guard raised != isIslandRaised else { return }
        withAnimation(Self.islandMotion) {
            isIslandRaised = raised
        }
    }
}

extension View {
    func shieldsPage(_ cover: PageCover, coordinator: AppCoordinator) -> some View {
        onHover { inside in
            coordinator.overlays.notePointer(on: cover, inside)
            if inside {
                NSCursor.arrow.set()
            }
        }
        .onDisappear { coordinator.overlays.notePointer(on: cover, false) }
    }
}
