// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import SwiftUI

nonisolated enum SplitMetrics {
    static let gutter: CGFloat = 0.5

    static let seamHitWidth: CGFloat = 10

    static let snapDistance: CGFloat = 18

    static func isCentred(_ fraction: CGFloat, over length: CGFloat) -> Bool {
        abs(fraction - 0.5) * length < snapDistance
    }

    static func snapped(_ fraction: CGFloat, over length: CGFloat) -> CGFloat {
        isCentred(fraction, over: length) ? 0.5 : fraction
    }

    static func seamHitRect(in rect: CGRect, axis: SplitAxis) -> CGRect {
        axis == .sideBySide
            ? CGRect(
                x: rect.midX - seamHitWidth / 2, y: rect.minY,
                width: seamHitWidth, height: rect.height
            )
            : CGRect(
                x: rect.minX, y: rect.midY - seamHitWidth / 2,
                width: rect.width, height: seamHitWidth
            )
    }
}

nonisolated struct SeamSnapTracker: Equatable {
    private var isEngaged = false

    mutating func resolve(_ fraction: CGFloat, over length: CGFloat) -> (share: CGFloat, snapped: Bool) {
        let centred = SplitMetrics.isCentred(fraction, over: length)
        defer { isEngaged = centred }
        return (centred ? 0.5 : fraction, centred && !isEngaged)
    }

    mutating func reset() {
        isEngaged = false
    }
}

@MainActor
final class FrameGate {
    private var lastPassed: CFTimeInterval = 0
    private var held: (() -> Void)?

    private static let interval: CFTimeInterval = {
        let hertz = NSScreen.main?.maximumFramesPerSecond ?? 60
        return 1 / CFTimeInterval(max(hertz, 60))
    }()

    func offer(_ change: @escaping () -> Void) {
        let now = CACurrentMediaTime()
        guard now - lastPassed >= Self.interval else {
            held = change
            return
        }
        lastPassed = now
        held = nil
        change()
    }

    func flush() {
        held?()
        held = nil
    }
}

struct SplitSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let settingsWorkspace: SettingsWorkspace
    let split: TabSplit
    let panes: [BrowserTab]

    @Environment(\.colorScheme) private var colorScheme
    let pull: PullState

    @State private var seamGrab: CGSize?
    @State private var seamSnap = SeamSnapTracker()
    @State private var gate = FrameGate()
    @State private var surfaceFrame: CGRect = .zero

    private var model: SidebarDragModel {
        coordinator.sidebarDrag
    }

    private var carriedPane: UUID? {
        model.carriedPaneID.flatMap { split.contains($0) ? $0 : nil }
    }

    private var restingGrid: TabSplit {
        guard let carried = carriedPane,
              let rest = TabSplits([restingSplit]).removing(carried).splits.first
        else { return restingSplit }
        return rest
    }

    private var restingSplit: TabSplit {
        split
    }

    private var aimed: SplitDropPlan.Target? {
        guard let target = model.target, restingGrid.contains(target.anchor) else { return nil }
        return target
    }

    private var isArming: Bool {
        aimed != nil
    }

    private func tab(_ id: UUID) -> BrowserTab? {
        panes.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                grid(in: proxy.size)
                handles(in: proxy.size)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                surfaceFrame = frame
            }
        }
        .animation(nil, value: split)
        .animation(Theme.Motion.settle, value: carriedPane)
    }

    // MARK: - Layout

    private func layout(in size: CGSize) -> SplitLayout {
        SplitLayout(grid: restingGrid, size: size, gutter: SplitMetrics.gutter)
    }

    private func grid(in size: CGSize) -> some View {
        let layout = layout(in: size)
        return ZStack(alignment: .topLeading) {
            ForEach(panes) { tab in
                if let rect = layout.slot(of: tab.id) {
                    pane(tab)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }

            seams(layout)

            if let aimed {
                SplitLandingSlot(
                    outcome: outcome(of: aimed),
                    topInset: 0
                )
                .frame(width: aimed.slot.width, height: aimed.slot.height)
                .offset(x: aimed.slot.minX, y: aimed.slot.minY)
                .transition(.identity)
                .animation(Theme.Motion.quick, value: aimed)
            }
        }
    }

    private func outcome(of target: SplitDropPlan.Target) -> SplitLandingSlot.Outcome {
        guard target.displaces else { return .arrives }
        return carriedPane == nil ? .replaces : .exchanges
    }

    private var seamsSitOnLightPages: Bool {
        PageInk.isLight(
            ChromeBand.pageColor(browser: browser, coordinator: coordinator),
            scheme: colorScheme
        )
    }

    private var seamColor: Color {
        Color(nsColor: LoomChrome.sampledColor(
            ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
            scheme: colorScheme
        ))
    }

    private func seams(_ layout: SplitLayout) -> some View {
        ForEach(layout.seams) { seam in
            SeamHandle(
                axis: seam.axis,
                onLightPage: seamsSitOnLightPages,
                seamColor: seamColor,
                onDragChanged: { point in resize(seam, to: point) },
                onDragEnded: {
                    seamGrab = nil
                    seamSnap.reset()
                    gate.flush()
                    browser.scheduleSave()
                },
                onReset: {
                    apply(seam, leading: 0.5)
                    browser.scheduleSave()
                }
            )
            .frame(width: seam.rect.width, height: seam.rect.height)
            .offset(x: seam.rect.minX, y: seam.rect.minY)
        }
        .allowsHitTesting(!isArming && carriedPane == nil)
    }

    private func resize(_ seam: SplitSeam, to pointInWindow: CGPoint) {
        let local = CGPoint(
            x: pointInWindow.x - surfaceFrame.minX,
            y: pointInWindow.y - surfaceFrame.minY
        )
        let grab: CGSize
        let firstReading = seamGrab == nil
        if let seamGrab {
            grab = seamGrab
        } else {
            grab = CGSize(width: local.x - seam.rect.midX, height: local.y - seam.rect.midY)
            seamGrab = grab
        }
        let aimedAt = CGPoint(x: local.x - grab.width, y: local.y - grab.height)
        let (share, snapped) = seamSnap.resolve(
            seam.leadingShare(at: aimedAt),
            over: seam.divisibleLength
        )
        if snapped, !firstReading {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        gate.offer { apply(seam, leading: share) }
    }

    private func apply(_ seam: SplitSeam, leading: CGFloat) {
        guard let anchor = restingGrid.leader.flatMap(tab) else { return }
        browser.setSplitSeam(
            seam,
            containing: anchor,
            leading: leading,
            minimum: seam.minimumShare(TabSplit.minimumPaneLength)
        )
    }

    private func pane(_ tab: BrowserTab) -> some View {
        WebPane(
            tab: tab,
            browser: browser,
            coordinator: coordinator,
            settingsWorkspace: settingsWorkspace,
            pull: tab.id == browser.activeTabID ? pull : .idle
        )
        .id(tab.id)
    }

    // MARK: - Grips

    /// Every grip stays in the tree, including the one being dragged. A view
    /// removed mid-gesture never delivers `.onEnded`, so it is hidden instead.
    private func handles(in size: CGSize) -> some View {
        let layout = layout(in: size)
        return ForEach(panes) { tab in
            PaneHandle(
                tab: tab,
                browser: browser,
                coordinator: coordinator,
                isHidden: carriedPane != nil || isArming,
                isFocused: tab.id == browser.activeTabID
            )
            .opacity(carriedPane == tab.id ? 0 : 1)
            .offset(
                x: handleCentre(tab, in: layout).x - PaneHandle.size.width / 2,
                y: handleCentre(tab, in: layout).y - PaneHandle.size.height / 2
            )
        }
    }

    private func handleCentre(_ tab: BrowserTab, in layout: SplitLayout) -> CGPoint {
        guard let rect = layout.slot(of: tab.id) else { return CGPoint(x: -1000, y: -1000) }
        let covered = 10 + PaneHandle.size.height / 2
        return CGPoint(x: rect.midX, y: rect.minY + covered)
    }
}

private struct WebPane: View {
    let tab: BrowserTab
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let settingsWorkspace: SettingsWorkspace
    let pull: PullState

    private var showsStartPage: Bool {
        ChromeBand.showsStartPage(for: tab)
    }

    var body: some View {
        surface
            .overlay {
                PaneEventCatcher(onPointerDown: { coordinator.focusPane(tab) })
            }

    }

    @ViewBuilder
    private var surface: some View {
        if let internalPage = tab.internalPage {
            InternalPageSurface(
                page: internalPage,
                browser: browser,
                coordinator: coordinator,
                settingsWorkspace: settingsWorkspace
            )
            .background(Theme.windowBackground)
        } else {
            page
                .overlay {
                    if showsStartPage {
                        StartPage(browser: browser, coordinator: coordinator)
                            .transition(.identity)
                    }
                }
        }
    }

    private var page: some View {
        WebViewRepresentable(
            webView: tab.webView,
            parksWhenIdle: true,
            onReady: { tab.webViewDidBecomeVisible() }
        )
            .opacity(showsStartPage ? 0 : 1)
            .background(showsStartPage ? Color.clear : tab.surfaceColor)
            .overlay {
                Theme.windowBackground
                    .opacity(!showsStartPage && !tab.hasPresentedContent ? 1 : 0)
                    .transition(.identity)
            }
            .offset(y: pull.offset)
            .overlay(alignment: .top) {
                tab.surfaceColor
                    .frame(height: pull.offset)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if pull.offset > 0 {
                    PullIndicator(state: pull)
                        .padding(.top, pull.offset / 2 - PullIndicator.size / 2)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if !showsStartPage {
                    LinkPreview(
                        address: tab.hoveredLink?.absoluteString,
                        intent: .of(coordinator.linkModifiers),
                        ground: tab.canvasColor
                    )
                }
            }
            .overlay {
                LinkPeekOverlay(peek: coordinator.linkPeek, tabID: tab.id)
            }
    }
}

struct SplitLandingSlot: View {
    nonisolated enum Outcome {
        case arrives
        case replaces
        case exchanges
    }

    let outcome: Outcome
    var topInset: CGFloat = 0

    static let inset: CGFloat = 6

    private var caption: LocalizedStringResource {
        switch outcome {
        case .arrives:
            "Drop the page here"
        case .replaces:
            "Take this page’s place"
        case .exchanges:
            "Swap with this page"
        }
    }

    private static var radius: CGFloat {
        Theme.Radius.nested(in: LoomChrome.canvasRadius, inset: inset)
    }

    var body: some View {
        LoomPanelFill(
            shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous),
            emphasis: 2.2
        )
            .overlay {
                Text(caption)
                    .font(Theme.Font.title)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(Self.inset)
            .padding(.top, topInset)
            .allowsHitTesting(false)
    }
}

private struct SeamHandle: View {
    let axis: SplitAxis
    let onLightPage: Bool
    let seamColor: Color
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
    let onReset: () -> Void

    @State private var hovering = false
    @State private var isDragging = false

    private var isSideBySide: Bool {
        axis == .sideBySide
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(seamColor)

            LoomResizePill(
                axis: isSideBySide ? .vertical : .horizontal,
                isVisible: hovering || isDragging,
                isDragging: isDragging,
                onLightPage: onLightPage
            )
        }
        .contentShape(SeamHitBand(axis: axis))
        .pointerStyle(isSideBySide ? .columnResize : .rowResize)
        .onHover { hovering = $0 }
        .gesture(drag)
        .onTapGesture(count: 2) { onReset() }
        .animation(Theme.Motion.quick, value: hovering)
        .animation(Theme.Motion.quick, value: isDragging)
        .help("Drag to resize · double-click to reset")
        .onDisappear {
            if hovering || isDragging {
                NSCursor.arrow.set()
            }
        }
    }

    private struct SeamHitBand: Shape {
        let axis: SplitAxis

        nonisolated func path(in rect: CGRect) -> Path {
            Path(SplitMetrics.seamHitRect(in: rect, axis: axis))
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                withTransaction(Transaction(animation: nil)) {
                    onDragChanged(value.location)
                }
            }
            .onEnded { _ in
                isDragging = false
                withTransaction(Transaction(animation: nil)) {
                    onDragEnded()
                }
            }
    }
}

nonisolated enum SplitPillVisibility {
    static let resting: Double = 0.35
    static let settleDelay = Duration.seconds(1.2)
    static let settleFade = 0.8

    static func isEngaged(isHidden: Bool, isHovered: Bool, isDragging: Bool, isSettled: Bool) -> Bool {
        !isHidden && (isHovered || isDragging || !isSettled)
    }

    static func opacity(isHidden: Bool, isHovered: Bool, isDragging: Bool, isSettled: Bool) -> Double {
        if isHidden {
            return 0
        }
        return isEngaged(
            isHidden: isHidden,
            isHovered: isHovered,
            isDragging: isDragging,
            isSettled: isSettled
        ) ? 1 : resting
    }
}

private struct PaneHandle: View {
    let tab: BrowserTab
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let isHidden: Bool
    let isFocused: Bool

    static let size = CGSize(width: 48, height: 16)

    @State private var hovering = false
    @State private var dragging = false
    @State private var settled = false

    private var model: SidebarDragModel {
        coordinator.sidebarDrag
    }

    private var split: TabSplit? {
        browser.splits.split(containing: tab.id)
    }

    private var dotInk: Color {
        if isFocused {
            return Color.white.opacity(0.8)
        }
        return hovering || dragging ? Theme.Wash.scrim : Theme.chrome(0.35)
    }

    private var visibility: Double {
        SplitPillVisibility.opacity(
            isHidden: isHidden,
            isHovered: hovering,
            isDragging: dragging,
            isSettled: settled
        )
    }

    private var wearsGlass: Bool {
        SplitPillVisibility.isEngaged(
            isHidden: isHidden,
            isHovered: hovering,
            isDragging: dragging,
            isSettled: settled
        )
    }

    var body: some View {
        ZStack {
            if isFocused, !wearsGlass {
                Capsule().fill(Theme.accent)
            }
            LoomPanelFill(
                shape: Capsule(),
                isVisible: wearsGlass,
                emphasis: isFocused ? 2.6 : 1,
                tint: isFocused ? Theme.accent : nil,
                isInteractive: true
            )
            .transaction { $0.animation = nil }
        }
        .overlay {
            Capsule().strokeBorder(Theme.Wash.strong, lineWidth: 0.5)
        }
        .overlay {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(dotInk)
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(wearsGlass ? 0 : 0.18), radius: 5, y: 2)
        .opacity(visibility)
        .contentShape(Capsule())
        .allowsHitTesting(!isHidden || dragging)
        .holdsWindowStillOnHover()
        .pointerStyle(dragging ? .grabActive : .grabIdle)
        .onHover { over in
            hovering = over
            if over {
                NSCursor.openHand.set()
            }
        }
        .onDisappear {
            if hovering || dragging {
                NSCursor.arrow.set()
            }
            guard dragging else { return }
            model.clearDrop()
            coordinator.movePane(tab, onto: nil, zone: .none, stayingOnThePage: true)
        }
        .gesture(drag)
        .onTapGesture { popUpMenu() }
        .contextMenu { menu }
        .help("Click for options · drag to move this page")
        .animation(Theme.Motion.quick, value: hovering)
        .animation(.easeOut(duration: SplitPillVisibility.settleFade), value: settled)
        .task {
            settled = false
            try? await Task.sleep(for: SplitPillVisibility.settleDelay)
            settled = true
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                model.panePointInWindow = value.location
                if !dragging {
                    dragging = true
                    model.source = .pane(tab.id)
                    coordinator.beginPaneDrag(tab)
                }
                if model.dropFrameInWindow.contains(value.location) {
                    model.aim(at: value.location)
                } else if model.target != nil {
                    model.target = nil
                }
            }
            .onEnded { value in
                let target = model.targetPaneID
                let zone = model.zone
                let landedOnThePage = model.contentFrameInWindow.contains(value.location)
                dragging = false
                NSCursor.arrow.set()
                model.clearDrop()
                coordinator.movePane(tab, onto: target, zone: zone, stayingOnThePage: landedOnThePage)
            }
    }

    private var canSwapRow: Bool {
        split?.sibling(of: tab.id) != nil
    }

    private func popUpMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let swap = menuItem(String(localized: "Swap Pages"), symbol: "arrow.left.arrow.right") {
            browser.swapSplitRow(containing: tab)
        }
        swap.isEnabled = canSwapRow
        menu.addItem(swap)

        if let axis = split?.axis {
            let title: String
            if axis == .stacked {
                title = String(localized: "Place Side by Side")
            } else {
                title = String(localized: "Stack Pages")
            }
            menu.addItem(menuItem(title, symbol: "rectangle.split.2x1") {
                browser.setSplitAxis(axis == .stacked ? .sideBySide : .stacked, containing: tab)
            })
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Remove This Page"), symbol: "rectangle.badge.minus") {
            browser.removeFromSplit(tab)
        })
        menu.addItem(menuItem(String(localized: "Exit Split"), symbol: "rectangle") {
            browser.dissolveSplit(containing: tab)
        })
        menu.addItem(.separator())
        menu.addItem(menuItem(String(localized: "Close This Page"), symbol: "xmark") {
            browser.close(tab)
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func menuItem(_ title: String, symbol: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(PillMenuAction.fire), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let target = PillMenuAction(action)
        item.target = target
        item.representedObject = target
        return item
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            browser.swapSplitRow(containing: tab)
        } label: {
            Label("Swap Pages", systemImage: "arrow.left.arrow.right")
        }
        .disabled(!canSwapRow)
        if let axis = split?.axis {
            Button {
                browser.setSplitAxis(axis == .stacked ? .sideBySide : .stacked, containing: tab)
            } label: {
                if axis == .stacked {
                    Label("Place Side by Side", systemImage: "rectangle.split.2x1")
                } else {
                    Label("Stack Pages", systemImage: "rectangle.split.2x1")
                }
            }
        }
        Divider()
        Button {
            browser.removeFromSplit(tab)
        } label: {
            Label("Remove This Page", systemImage: "rectangle.badge.minus")
        }
        Button {
            browser.dissolveSplit(containing: tab)
        } label: {
            Label("Exit Split", systemImage: "rectangle")
        }
        Divider()
        Button(role: .destructive) {
            browser.close(tab)
        } label: {
            Label("Close This Page", systemImage: "xmark")
        }
    }
}

private final class PillMenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}

private struct PaneEventCatcher: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }

    final class CatcherView: NSView {
        var onPointerDown: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard super.hitTest(point) != nil,
                  let event = window?.currentEvent ?? NSApp.currentEvent,
                  let onPointerDown
            else { return nil }
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                Task { onPointerDown() }
            default:
                break
            }
            return nil
        }
    }
}
