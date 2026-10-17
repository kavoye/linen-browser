// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreImage
import SwiftUI

struct BrowserView: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }
    @State private var containerWidth: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var mountsStandard: Bool
    @State private var mountsMinimal: Bool
    @State private var isRetracted: Bool
    @State private var isPageFull: Bool
    @State private var isLeavingMinimal = false
    @State private var isInputLocked = false
    @State private var switchGeneration = 0
    @State private var sidebarFrame: CGRect = .zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let retractMotion = Animation.spring(duration: 0.34, bounce: 0)
    static let morphMotion = Animation.spring(duration: 0.35, bounce: 0)

    init(browser: BrowserModel, coordinator: AppCoordinator) {
        self.browser = browser
        self.coordinator = coordinator
        let isMinimal = coordinator.settings.isMinimal
        _mountsStandard = State(initialValue: !isMinimal)
        _mountsMinimal = State(initialValue: isMinimal)
        _isRetracted = State(initialValue: isMinimal)
        _isPageFull = State(initialValue: isMinimal)
    }

    private var isSettledMinimal: Bool {
        mountsMinimal && !mountsStandard
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

    private var roomBesideSidebar: CGFloat {
        containerWidth - (sidebar.isVisible ? sidebar.openWidth(in: containerWidth) : 0)
    }

    private var standardGeometry: LoomShellGeometry {
        LoomShellGeometry(
            containerWidth: containerWidth,
            sidebarWidth: sidebar.openWidth(in: containerWidth),
            preferredPanelWidth: panel.openWidth(in: roomBesideSidebar),
            isSidebarVisible: sidebar.isVisible,
            isPanelVisible: showsPanel,
            isPanelExpanded: showsPanel && panel.isExpanded
        )
    }

    private func endPeekUnlessPointerOnSidebar() {
        guard sidebar.isPeeking, !sidebar.isVisible, !coordinator.overlays.isProfileSwitcherOpen else { return }
        if let pointer = coordinator.pointerInShell, sidebarFrame.contains(pointer) {
            return
        }
        sidebar.isPeeking = false
    }

    private var page: some View {
        let barOnTop = coordinator.settings.minimalBarEdge == .top
        let isNative = ContentArea.showsPanelFill(browser: browser)
        let pageSize = isMorphing ? (isNative ? morphRect.size : isRetracted ? fullRect.size : standardRect.size) : nil
        let ground = isMorphing && !isNative ? browser.activeTab?.surfaceColor ?? Theme.windowBackground : .clear
        return ContentArea(
            browser: browser,
            coordinator: coordinator,
            settingsWorkspace: coordinator.settingsWorkspace,
            canvasTrailingInset: isPageFull || isMorphing ? 0 : standardGeometry.canvasTrailingInset,
            isFullBleed: isSettledMinimal,
            retraction: isPageFull || isMorphing ? 1 : 0,
            isFilled: isMorphing && isRetracted,
            findBarTop: isSettledMinimal && barOnTop ? IslandBar.edgeGap + IslandBar.height + 10 : 10
        )
        .frame(width: pageSize?.width, height: pageSize?.height)
        .animation(isNative ? Self.morphMotion : nil, value: isRetracted)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, !isMorphing && sidebar.isVisible && !isPageFull ? sidebar.openWidth(in: containerWidth) : 0)
        .background(ground)
        .visualEffect { [origin = morphRect.origin] content, _ in
            content.offset(x: origin.x, y: origin.y)
        }
        .clipShape(CanvasCutout(rect: morphRect, radius: isMorphing ? LoomChrome.canvasRadius : 0))
        .background {
            CanvasShadow(rect: morphRect.offsetBy(dx: 0, dy: 4))
                .opacity(isMorphing && !isRetracted ? 0.18 : 0)
        }
    }

    private var isMorphing: Bool {
        mountsStandard && mountsMinimal
    }

    private var fullRect: CGRect {
        CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
    }

    private var standardRect: CGRect {
        let leading = (sidebar.isVisible ? sidebar.openWidth(in: containerWidth) : 0) + LoomChrome.canvasInset
        let trailing = LoomChrome.canvasInset + standardGeometry.canvasTrailingInset
        return CGRect(
            x: leading,
            y: LoomChrome.canvasTop,
            width: max(0, containerWidth - leading - trailing),
            height: max(0, containerHeight - LoomChrome.canvasTop - LoomChrome.canvasInset)
        )
    }

    private var morphRect: CGRect {
        isMorphing && !isRetracted ? standardRect : fullRect
    }

    @ViewBuilder private var standardChrome: some View {
        let width = sidebar.openWidth(in: containerWidth)
        let sidebarIn = sidebar.isShowing && !isRetracted
        let isExpanded = showsPanel && panel.isExpanded
        let shell = standardGeometry
        let lift = isRetracted ? -LoomChrome.canvasTop : 0
        let slide = isRetracted && sidebar.isShowing ? -(width + LoomChrome.canvasInset) : 0

        ZStack(alignment: .leading) {
            SidePanelSurface(
                browser: browser,
                coordinator: coordinator
            )
            .frame(width: shell.panelWidth)
            .padding(.top, isPageFull ? LoomChrome.canvasInset : LoomChrome.canvasTop)
            .padding(.trailing, LoomChrome.canvasInset)
            .padding(.bottom, LoomChrome.canvasInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(x: showsPanel ? 0 : shell.panelWidth + LoomChrome.canvasInset + 24)

            if showsPanel && !isExpanded {
                LoomPageInkReader(browser: browser, coordinator: coordinator) { onLightPage in
                    LoomColumnResizeHandle(
                        grabWidth: LoomChrome.resizeGrabWidth,
                        onLightPage: onLightPage,
                        isDragging: panel.isDragging,
                        onDragChanged: {
                            panel.dragChanged(translation: $0, available: roomBesideSidebar)
                        },
                        onDragEnded: {
                            panel.dragEnded(translation: $0, available: roomBesideSidebar)
                        },
                        onReset: { panel.resetWidth() }
                    )
                }
                .padding(.top, isPageFull ? LoomChrome.canvasInset : LoomChrome.canvasTop)
                .padding(.bottom, LoomChrome.canvasInset)
                .offset(x: shell.panelResizeLeading)
            }

            ContentNavBar(browser: browser, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.leading, sidebar.isVisible ? width : 0)
                .visualEffect { content, _ in content.offset(y: lift) }

            Sidebar(
                browser: browser,
                coordinator: coordinator
            )
            .frame(width: width)
            .environment(\.sidebarStyle, sidebar.style)
            .environment(\.sidebarWidth, width)
            .environment(\.sidebarIsFloating, sidebar.isFloating)
            .environment(\.sidebarTopRowShift, CGSize(width: -slide, height: lift))
            .environment(\.sidebarHidesMediaCard, isRetracted)
            .compositingGroup()
            .shadow(
                color: .black.opacity(sidebar.isFloating ? 0.45 : 0),
                radius: 22,
                x: 6
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                sidebarFrame = $0
            }
            .offset(x: sidebar.isShowing ? 0 : -(width + 24))
            .visualEffect { content, _ in content.offset(x: slide) }
            .onHover { inside in
                if !inside {
                    endPeekUnlessPointerOnSidebar()
                }
            }
            .onChange(of: coordinator.overlays.isProfileSwitcherOpen) { _, isOpen in
                if !isOpen {
                    endPeekUnlessPointerOnSidebar()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                endPeekUnlessPointerOnSidebar()
            }

            if sidebarIn {
                LoomPageInkReader(browser: browser, coordinator: coordinator) { onLightPage in
                    LoomColumnResizeHandle(
                        grabWidth: LoomChrome.resizeGrabWidth,
                        onLightPage: onLightPage,
                        isDragging: sidebar.isDragging,
                        onDragChanged: {
                            sidebar.dragChanged(translation: $0, container: containerWidth)
                        },
                        onDragEnded: {
                            sidebar.dragEnded(translation: $0, container: containerWidth)
                        },
                        onReset: { sidebar.resetWidth() }
                    )
                }
                .padding(.top, LoomChrome.canvasTop)
                .padding(.bottom, LoomChrome.canvasInset)
                .offset(
                    x: shell.sidebarResizeLeading
                )
            }

            SidebarVisibilityToggle(browser: browser, coordinator: coordinator)
                .visualEffect { content, _ in content.offset(y: lift) }

            TabPreviewOverlay(
                browser: browser,
                model: coordinator.tabPreview,
                sidebarEdge: sidebar.isShowing ? width : 0,
                github: coordinator.settings.showsGitHub && coordinator.github.canPreview ? coordinator.github : nil
            )
            .modifier(LoomInk(browser: browser, coordinator: coordinator, reach: .scheme))

            GitHubPreviewOverlay(presenter: coordinator.githubPreview, model: coordinator.github)
                .modifier(LoomInk(browser: browser, coordinator: coordinator, reach: .scheme))

            SidebarDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .modifier(LoomInk(browser: browser, coordinator: coordinator, reach: .window))
                .environment(\.sidebarStyle, sidebar.style)

            DownloadFlightLayer(flights: coordinator.downloadFlights)
                .environment(\.sidebarStyle, sidebar.style)

            PaneDragOverlay(browser: browser, model: coordinator.sidebarDrag)
                .modifier(LoomInk(browser: browser, coordinator: coordinator, reach: .window))

            if browser.isSwitchingTabs {
                TabSwitcherOverlay(
                    browser: browser,
                    onClose: { coordinator.closeAskingIfPinned($0) },
                    onToggleMute: { coordinator.toggleMute(tab: $0) }
                )
                .modifier(LoomInk(browser: browser, coordinator: coordinator, reach: .scheme))
            }

            if !sidebar.isShowing && !isRetracted {
                Color.clear
                    .frame(width: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { sidebar.isPeeking = true } }
            }

            if coordinator.palette.isOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closePalette() }
            }

            CommandPaletteLayer(browser: browser, coordinator: coordinator)
                .modifier(LoomInk(browser: browser, coordinator: coordinator))

            ProfileSwitcherLayer(coordinator: coordinator)
                .modifier(LoomInk(browser: browser, coordinator: coordinator))
        }
    }

    var body: some View {
        ZStack {
            shell
                .frame(
                    width: coordinator.frozenShellSize?.width,
                    height: coordinator.frozenShellSize?.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if coordinator.onboarding.isPresented {
                OnboardingOverlay(coordinator: coordinator, model: coordinator.onboarding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
        .onChange(of: coordinator.settings.isMinimal) { _, isMinimal in
            switchShell(toMinimal: isMinimal)
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
            coordinator.palette.isOpen ? Theme.Motion.settle : nil,
            value: coordinator.palette.isOpen
        )
        .animation(
            coordinator.overlays.isProfileSwitcherOpen ? Theme.Motion.quick : nil,
            value: coordinator.overlays.isProfileSwitcherOpen
        )
        .animation(nil, value: coordinator.onboarding.isPresented)
    }

    private var shell: some View {
        ZStack(alignment: .leading) {
            if mountsStandard {
                LoomSpaceBackdrop(browser: browser, coordinator: coordinator)
            }

            page

            if mountsStandard {
                standardChrome
                    .allowsHitTesting(!isInputLocked && !isRetracted)
            }

            if mountsMinimal {
                MinimalShell(
                    browser: browser,
                    coordinator: coordinator,
                    isLeaving: isLeavingMinimal
                )
                .allowsHitTesting(!isInputLocked && isRetracted)
            }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            containerWidth = frame.width
            containerHeight = frame.height
            coordinator.noteShellFrame(frame)
        }
    }

    private func switchShell(toMinimal: Bool) {
        switchGeneration += 1
        let generation = switchGeneration
        guard !reduceMotion else {
            cut {
                isRetracted = toMinimal
                isPageFull = toMinimal
                isLeavingMinimal = false
                mountsStandard = !toMinimal
                mountsMinimal = toMinimal
                isInputLocked = false
            }
            return
        }
        Task { @MainActor in
            cut {
                isInputLocked = true
                isPageFull = toMinimal
                if toMinimal, !mountsMinimal {
                    isLeavingMinimal = true
                    mountsMinimal = true
                }
                if !toMinimal {
                    mountsStandard = true
                }
            }
            await Task.yield()
            guard generation == switchGeneration else { return }
            withAnimation(Self.morphMotion) {
                isRetracted = toMinimal
            } completion: {
                guard generation == switchGeneration else { return }
                isInputLocked = false
            }
            withAnimation(Self.morphMotion, completionCriteria: .removed) {
                isLeavingMinimal = !toMinimal
            } completion: {
                guard generation == switchGeneration else { return }
                cut {
                    mountsStandard = !toMinimal
                    mountsMinimal = toMinimal
                    isLeavingMinimal = false
                    isPageFull = toMinimal
                }
            }
        }
    }

    private func cut(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

struct CommandPaletteLayer: View {
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
                        .id(coordinator.palette.token)
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
        .onAppear { follow(coordinator.palette.isOpen) }
        .onChange(of: coordinator.palette.isOpen) { _, isOpen in follow(isOpen) }
    }

    private func follow(_ isOpen: Bool) {
        pending?.cancel()
        isMoving = true
        if isOpen {
            let coordinator = coordinator
            let opened = CommandPaletteModel(browser: browser, coordinator: coordinator) {
                coordinator.closePalette()
            }
            if let seed = coordinator.palette.seed {
                opened.interaction.query = seed
            }
            model = opened
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
    @Entry var sidebarTopRowShift = CGSize.zero
    @Entry var sidebarHidesMediaCard = false
}

private struct CanvasShadow: View {
    let rect: CGRect

    private static let blur: CGFloat = 12
    private static let spread = blur * 3
    private static let cap = spread + LoomChrome.canvasRadius
    private static let image = render()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable(
                capInsets: EdgeInsets(top: Self.cap, leading: Self.cap, bottom: Self.cap, trailing: Self.cap),
                resizingMode: .stretch
            )
            .frame(width: rect.width + Self.spread * 2, height: rect.height + Self.spread * 2)
            .offset(x: rect.minX - Self.spread, y: rect.minY - Self.spread)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    private static func render() -> NSImage {
        let scale: CGFloat = 2
        let side = (cap * 2 + 2) * scale
        let pixels = Int(side)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage() }
        let inset = spread * scale
        let shape = Path(
            roundedRect: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2),
            cornerRadius: LoomChrome.canvasRadius * scale,
            style: .continuous
        )
        context.addPath(shape.cgPath)
        context.setFillColor(.black)
        context.fillPath()
        guard let sharp = context.makeImage() else { return NSImage() }
        let source = CIImage(cgImage: sharp)
        let blurred = source.applyingGaussianBlur(sigma: blur * scale).cropped(to: source.extent)
        guard let image = CIContext().createCGImage(blurred, from: source.extent) else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: side / scale, height: side / scale))
    }
}

private nonisolated struct CanvasCutout: Shape {
    var rect: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(rect.minX, rect.minY), AnimatablePair(rect.width, rect.height)) }
        set {
            rect = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in _: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}
