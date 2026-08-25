// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private enum WorkspaceListCoordinateSpace {
    static let name = "sidebar-workspace"
}

private struct WorkspaceListFadeMask: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black)

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.45), location: 0.68),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42)
        }
    }
}

struct WorkspaceList<TopBar: View, BottomBar: View>: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let selection: SidebarSelection
    let newFolderDrop: SidebarNewFolderDrop
    let frames: SidebarFrames
    let bottomClearance: CGFloat
    let topBar: TopBar
    let bottomBar: BottomBar
    let contentInsets: EdgeInsets

    @State private var armed: SidebarDropIntent?
    @State private var armCandidate: (intent: SidebarDropIntent, since: Date)?

    private var model: SidebarDragModel {
        coordinator.sidebarDrag
    }
    private var drag: SidebarDrag? {
        model.drag
    }
    private var listOrigin: CGPoint {
        model.listOriginInWindow
    }

    private var context: SidebarRowContext {
        SidebarRowContext(
            browser: browser,
            coordinator: coordinator,
            selection: selection,
            drag: drag,
            armed: armed,
            candidate: armCandidate?.intent,
            offersSplit: model.carriedTabID != nil,
            space: WorkspaceListCoordinateSpace.name,
            frames: frames
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                SidebarRows(items: browser.sidebarItems, depth: 0, context: context)

                Color.clear
                    .frame(height: 26 + bottomClearance)
                    .contentShape(Rectangle())
                    .onTapGesture { selection.takeKeyboard() }
                    .animation(Theme.Motion.drift, value: bottomClearance)
            }
            .padding(.leading, contentInsets.leading)
            .padding(.trailing, contentInsets.trailing)
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .mask {
            WorkspaceListFadeMask()
        }
        .safeAreaBar(edge: .top, spacing: 6) {
            topBar
                .padding(.leading, contentInsets.leading)
                .padding(.trailing, contentInsets.trailing)
        }
        .safeAreaBar(edge: .bottom, spacing: 6) {
            bottomBar
                .padding(.leading, contentInsets.leading)
                .padding(.trailing, contentInsets.trailing)
                .zIndex(1)
        }
        .coordinateSpace(.named(WorkspaceListCoordinateSpace.name))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.listOriginInWindow = $0.origin }
        // The gesture belongs to the container. A reorder rebuilds the dragged
        // row, and a rebuilt view never delivers `.onEnded`.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(WorkspaceListCoordinateSpace.name))
                .onChanged(dragChanged)
                .onEnded(dragEnded)
        )
        .background {
            SidebarKeyCatcher(
                isActive: selection.ownsKeyboard,
                onSelectAll: { selection.selectAll(in: browser.sidebarTree, isExpanded: isExpanded) },
                onClear: { selection.clear() }
            )
        }
        .onChange(of: browser.sidebarTree) { _, tree in
            selection.prune(to: Set(tree.walk()))
        }
    }

    private func isExpanded(_ folderID: UUID) -> Bool {
        browser.folder(id: folderID)?.isExpanded ?? false
    }

    private var liveFrames: [SidebarItem: CGRect] {
        frames.live(
            tabIDs: Set(browser.tabs.map(\.id)).subtracting(browser.hiddenSidebarTabIDs),
            folderIDs: Set(browser.folders.map(\.id))
        )
    }

    private func dragChanged(_ value: DragGesture.Value) {
        let slots = liveFrames
        if drag == nil || drag?.landing == true {
            guard let hit = slots.first(where: { $0.value.contains(value.startLocation) })
            else { return }
            let carried = browser.withSplitMembers(
                selection.carried(startingOn: hit.key, in: browser.sidebarTree)
            )
            model.drag = SidebarDrag(
                items: carried,
                lead: hit.key,
                origin: hit.value,
                tree: browser.sidebarTree
            )
            model.source = .row
            coordinator.tabPreview.beginSuppression()
        }
        model.drag?.translation = value.translation

        let inWindow = CGPoint(x: value.location.x + listOrigin.x, y: value.location.y + listOrigin.y)
        let overButton = newFolderDrop.frame.contains(inWindow)
        if overButton != newFolderDrop.isArmed {
            withAnimation(Theme.Motion.quick) { newFolderDrop.isArmed = overButton }
        }
        guard !overButton else {
            disarm()
            return
        }

        if model.carriedTabID != nil, !coordinator.isShowingSettings,
           model.dropFrameInWindow.contains(inWindow) {
            model.aim(at: inWindow)
        } else if model.target != nil {
            model.target = nil
        }
        guard !model.contentFrameInWindow.contains(inWindow) else {
            disarm()
            return
        }

        if let drag {
            react(
                at: CGPoint(
                    x: value.location.x,
                    y: SidebarDropGeometry.probeY(
                        cursorY: value.location.y,
                        carriedMidY: drag.origin.midY + drag.translation.height,
                        carriedHeight: drag.origin.height
                    )
                ),
                in: slots
            )
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        defer {
            disarm()
            newFolderDrop.isArmed = false
            coordinator.tabPreview.endSuppression()
            model.clearDrop()
        }
        guard let drag, !drag.landing else { return }
        let lead = drag.lead

        if model.zone != .none, let id = model.carriedTabID, let tab = browser.tab(id: id) {
            coordinator.dropOnPage(tab, onto: model.targetPaneID, zone: model.zone)
            selection.clear()
        } else if newFolderDrop.isArmed {
            browser.createFolder(containing: drag.items)
            selection.clear()
        } else if let armed {
            switch armed {
            case .fold(.folder(let folderID)):
                if let folder = browser.folder(id: folderID) {
                    browser.move(drag.items, into: folder)
                }
            case .fold(.tab(let targetID)):
                browser.createFolder(containing: browser.withSplitMembers([.tab(targetID)]) + drag.items)
                selection.clear()
            case .split(.tab(let targetID), let leading):
                if let target = browser.tab(id: targetID),
                   let carried = model.carriedTabID.flatMap({ browser.tab(id: $0) }) {
                    coordinator.dropOnPage(carried, onto: targetID, zone: leading ? .left : .right)
                    _ = target
                }
                selection.clear()
            case .split(.folder, _):
                break
            }
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            model.drag?.landing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            if model.drag?.lead == lead, model.drag?.landing == true {
                model.drag = nil
            }
        }
    }

    private func react(at point: CGPoint, in slots: [SidebarItem: CGRect]) {
        guard let drag else { return }

        guard let hit = slots.first(where: {
            !drag.carries($0.key) && $0.value.minY <= point.y && point.y < $0.value.maxY
        }) else {
            if let lowest = slots.values.map(\.maxY).max(), point.y > lowest {
                disarm()
                browser.move(drag.items, into: nil, before: nil)
            }
            return
        }
        let frame = hit.value
        let tree = browser.sidebarTree

        let band: SidebarDropBand
        let foldable: Bool
        switch hit.key {
        case .folder(let folderID):
            band = SidebarDropGeometry.folderBand(y: point.y, in: frame)
            foldable = tree.canHold(folderID, drag.items)
                && drag.items.first.flatMap({ tree.parent(of: $0) }) != folderID
        case .tab:
            if tree.parent(of: hit.key) != nil {
                band = SidebarDropGeometry.folderedTabBand(y: point.y, in: frame)
                foldable = false
            } else {
                foldable = !drag.carriesFolder
                band = SidebarDropGeometry.looseTabBand(
                    at: point,
                    in: frame,
                    canFold: foldable,
                    canSplit: canSplit(with: hit.key),
                    splitEndWidth: SidebarMetrics.splitEndWidth(style: coordinator.sidebar.style)
                )
            }
        }

        switch band {
        case .before, .after:
            disarm()
            place(drag.items, before: band == .before, of: hit.key)
        case .fold:
            if foldable {
                considerArming(.fold(hit.key))
            } else {
                disarm()
            }
        case .split(let leading):
            considerArming(.split(hit.key, leading: leading))
        }
    }

    private func canSplit(with target: SidebarItem) -> Bool {
        guard let carried = model.carriedTabID, case .tab(let targetID) = target else { return false }
        guard carried != targetID else { return false }
        guard let grid = browser.splits.split(containing: targetID) else { return true }
        return !grid.isFull && !grid.contains(carried)
    }

    private func place(_ items: [SidebarItem], before: Bool, of anchor: SidebarItem) {
        let tree = browser.sidebarTree
        let home = tree.parent(of: anchor)
        let siblings = tree.rows(in: home)
        guard let index = siblings.firstIndex(of: anchor) else { return }
        let target: SidebarItem? = before
            ? anchor
            : (index + 1 < siblings.endIndex ? siblings[index + 1] : nil)
        browser.move(items, into: home.flatMap(browser.folder(id:)), before: target)
    }

    private func considerArming(_ target: SidebarDropIntent) {
        guard armed != target else { return }
        if let candidate = armCandidate, candidate.intent == target {
            if Date.now.timeIntervalSince(candidate.since) >= 0.2 {
                arm(target)
            }
            return
        }
        armCandidate = (target, Date.now)
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard let drag, !drag.landing, armCandidate?.intent == target else { return }
            arm(target)
        }
    }

    private func arm(_ target: SidebarDropIntent) {
        guard armed != target else { return }
        withAnimation(Theme.Motion.quick) { armed = target }
    }

    private func disarm() {
        armCandidate = nil
        if armed != nil {
            withAnimation(.easeOut(duration: 0.1)) { armed = nil }
        }
    }
}

struct SidebarDragOverlay: View {
    let browser: BrowserModel
    let model: SidebarDragModel

    @Environment(\.sidebarStyle) private var sidebarStyle

    var body: some View {
        GeometryReader { proxy in
            if let drag = model.drag {
                let origin = proxy.frame(in: .global).origin
                SidebarDragStack(drag: drag, browser: browser)
                    .frame(width: drag.origin.width, height: drag.origin.height)
                    .scaleEffect(drag.landing ? 1 : SidebarDragGhost.liftScale(style: sidebarStyle))
                    .opacity(drag.landing ? 0 : 1)
                    .offset(
                        x: model.listOriginInWindow.x - origin.x + chipX(drag),
                        y: model.listOriginInWindow.y - origin.y + chipY(drag)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func chipX(_ drag: SidebarDrag) -> CGFloat {
        guard !drag.landing else { return drag.origin.minX }
        return drag.origin.minX + drag.translation.width
    }

    private func chipY(_ drag: SidebarDrag) -> CGFloat {
        guard !drag.landing else { return model.frames[drag.lead]?.minY ?? drag.origin.minY }
        return drag.origin.minY + drag.translation.height
    }
}

struct PaneDragOverlay: View {
    let browser: BrowserModel
    let model: SidebarDragModel

    private static let size = CGSize(width: 190, height: 32)

    var body: some View {
        GeometryReader { proxy in
            if let id = model.carriedPaneID {
                let origin = proxy.frame(in: .global).origin
                SidebarDragChip(item: .tab(id), browser: browser)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .offset(
                        x: model.panePointInWindow.x - origin.x - Self.size.width / 2,
                        y: model.panePointInWindow.y - origin.y - Self.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SidebarDragStack: View {
    let drag: SidebarDrag
    let browser: BrowserModel

    private static let step: CGFloat = 4

    private var behind: [SidebarItem] {
        Array(drag.items.filter { $0 != drag.lead }.prefix(2))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(behind.enumerated()).reversed(), id: \.element) { index, item in
                SidebarDragChip(item: item, browser: browser)
                    .offset(
                        x: CGFloat(index + 1) * Self.step,
                        y: CGFloat(index + 1) * Self.step
                    )
                    .opacity(1 - Double(index + 1) * 0.22)
            }
            SidebarDragChip(item: drag.lead, browser: browser)
        }
        .overlay(alignment: .topTrailing) {
            if !drag.isSingle {
                Text(drag.items.count, format: .number)
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Theme.accent, in: Capsule())
                    .offset(x: 5, y: -6)
            }
        }
    }
}

struct SidebarDragChip: View {
    let item: SidebarItem
    let browser: BrowserModel

    @Environment(\.sidebarStyle) private var sidebarStyle

    var body: some View {
        content
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Theme.windowBackground.opacity(SidebarDragGhost.chipFillOpacity),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Wash.hover, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 11, y: 5)
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .tab(let id):
            if let tab = browser.tab(id: id) {
                HStack(spacing: 8) {
                    TabIcon(tab: tab)
                    if sidebarStyle == .full {
                        Text(verbatim: tab.title)
                            .font(Theme.Font.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .folder(let id):
            if let folder = browser.folder(id: id) {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(folder.color.tint)
                    if sidebarStyle == .full {
                        Text(verbatim: folder.name)
                            .font(Theme.Font.control)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct SidebarKeyCatcher: NSViewRepresentable {
    let isActive: Bool
    let onSelectAll: () -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onSelectAll = onSelectAll
        nsView.onClear = onClear
        guard let window = nsView.window else { return }
        if isActive {
            if window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        } else if window.firstResponder === nsView {
            window.makeFirstResponder(nil)
        }
    }

    final class CatcherView: NSView {
        var onSelectAll: (() -> Void)?
        var onClear: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func selectAll(_ sender: Any?) {
            onSelectAll?()
        }

        override func cancelOperation(_ sender: Any?) {
            onClear?()
        }
    }
}
