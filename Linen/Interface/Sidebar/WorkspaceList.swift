// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private nonisolated enum WorkspaceListCoordinateSpace {
    static let name = "sidebar-workspace"
}

private enum SpringLoad {
    static let dwell: Duration = .milliseconds(250)
    static let spaceDwell: Duration = .milliseconds(450)
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
    let pinDrop: SidebarPinDrop
    let frames: SidebarFrames
    let bottomClearance: CGFloat
    let topBar: TopBar
    let bottomBar: BottomBar
    let contentInsets: EdgeInsets

    @State private var pinsCarried = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var reopening: [UUID] = []
    @State private var dwelling: UUID?
    @State private var dwell: Task<Void, Never>?
    @State private var spaceDwell: Task<Void, Never>?

    private var model: SidebarDragModel {
        coordinator.sidebarDrag
    }
    private var drag: SidebarDrag? {
        model.drag
    }
    private var listOrigin: CGPoint {
        model.listOriginInWindow
    }

    private var plan: SidebarSectionPlan {
        let carried = drag?.covered ?? []
        return SidebarSectionPlan(
            rows: browser.sidebarItems.map { item in
                SidebarSectionPlan.Row(
                    item: item,
                    isKept: browser.isKept(item, ignoring: carried),
                    isCarried: carried.contains(item)
                )
            },
            wasKept: drag?.wasKept == true
        )
    }

    private var sections: (kept: [SidebarItem], loose: [SidebarItem]) {
        if let held = coordinator.overlays.spaceSlide.held {
            let kept = held.prefix { browser.isKept($0) }
            return (Array(kept), Array(held.dropFirst(kept.count)))
        }
        let items = browser.sidebarItems
        let cut = plan.cut(pinsCarried: pinsCarried)
        guard cut > 0 else { return ([], items) }
        return (Array(items.prefix(cut)), Array(items.dropFirst(cut)))
    }

    private var context: SidebarRowContext {
        SidebarRowContext(
            browser: browser,
            coordinator: coordinator,
            selection: selection,
            drag: drag,
            isLeaving: model.isLeaving,
            incoming: model.incoming,
            arriving: model.arriving,
            pinsCarried: pinsCarried,
            space: WorkspaceListCoordinateSpace.name,
            frames: frames
        )
    }

    @ViewBuilder
    private var emptySpaceMenu: some View {
        Button {
            coordinator.requestNewTab()
        } label: {
            Label("New Tab", systemImage: "plus")
        }

        Button {
            _ = browser.createFolder(containing: [] as [SidebarItem])
        } label: {
            Label("New Folder…", systemImage: "folder.badge.plus")
        }

        if browser.tabs.count > 1 {
            Divider()

            Button {
                coordinator.organizeTabs()
            } label: {
                Label("Organize Tabs…", systemImage: "folder.badge.gearshape")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                let sections = sections
                if !sections.kept.isEmpty {
                    SidebarRows(items: sections.kept, depth: 0, context: context, ownsEnd: false)
                    SidebarSectionSeam()
                }

                SidebarRows(items: sections.loose, depth: 0, context: context)

                Color.clear
                    .frame(height: 26 + bottomClearance)
                    .contentShape(Rectangle())
                    .onTapGesture { selection.takeKeyboard() }
                    .contextMenu { emptySpaceMenu }
                    .animation(Theme.Motion.drift, value: bottomClearance)
            }
            .padding(.leading, contentInsets.leading)
            .padding(.trailing, contentInsets.trailing)
            .modifier(SpaceListInk(browser: browser, coordinator: coordinator))
            .modifier(SpaceSlideOffset(slide: coordinator.overlays.spaceSlide))
            .opacity(coordinator.overlays.spaceSlide.isGliding ? 0 : 1)
            .animation(nil, value: coordinator.overlays.spaceSlide.isGliding)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollDisabled(coordinator.overlays.spaceSlide.isSliding)
        .scrollPosition($scrollPosition)
        .onChange(of: browser.currentSpaceID) { _, _ in
            scrollPosition.scrollTo(edge: .top)
        }
        .overlay(alignment: .top) {
            SpacePeerList(
                browser: browser,
                coordinator: coordinator,
                slide: coordinator.overlays.spaceSlide,
                contentInsets: contentInsets
            )
            .opacity(coordinator.overlays.spaceSlide.isGliding ? 0 : 1)
            .animation(nil, value: coordinator.overlays.spaceSlide.isGliding)
        }
        .overlay {
            SpaceGlideStage(coordinator: coordinator, contentInsets: contentInsets)
        }
        .overlay(alignment: .trailing) {
            SpaceCreatePull(slide: coordinator.overlays.spaceSlide)
        }
        .scrollEdgeEffectHidden(true, for: .bottom)
        .onGeometryChange(for: CGRect.self) { proxy in
            let frame = proxy.frame(in: .named(WorkspaceListCoordinateSpace.name))
            let insets = proxy.safeAreaInsets
            return CGRect(
                x: frame.minX,
                y: frame.minY + insets.top,
                width: frame.width,
                height: max(0, frame.height - insets.top - insets.bottom)
            )
        } action: { model.listViewport = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            coordinator.overlays.spaceSlide.width = $0 + 24
        }
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
        .contextMenu { emptySpaceMenu }
        .coordinateSpace(.named(WorkspaceListCoordinateSpace.name))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            model.listOriginInWindow = $0.origin
            model.listSizeInWindow = $0.size
        }
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

    private func collapse(_ items: [SidebarItem]) -> [UUID] {
        var closed: [UUID] = []
        for case .folder(let id) in items {
            guard let folder = browser.folder(id: id), folder.isExpanded else { continue }
            folder.isExpanded = false
            closed.append(id)
        }
        return closed
    }

    private func isExpanded(_ folderID: UUID) -> Bool {
        browser.folder(id: folderID)?.isExpanded ?? false
    }

    private var liveFrames: [SidebarItem: CGRect] {
        frames.visible(in: browser)
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
                tree: browser.sidebarTree,
                keepsSection: browser.sidebarItems.contains { item in
                    guard case .tab(let id) = item else { return false }
                    return browser.tab(id: id)?.pinnedURL != nil
                },
                wasKept: carried.contains { browser.isKept($0) }
            )
            pinsCarried = model.drag?.wasKept == true
            model.source = .row
            reopening = collapse(carried)
            coordinator.tabPreview.beginSuppression()
        }
        model.drag?.translation = value.translation

        let pointer = NSEvent.mouseLocation
        if let lifted = model.drag, !coordinator.profiles.isPrivate {
            model.floatOrigin = CGPoint(
                x: pointer.x - value.startLocation.x + lifted.origin.minX,
                y: pointer.y + value.startLocation.y - lifted.origin.minY
            )
        }
        if model.floatOrigin != nil, let window = coordinator.nativeWindow, !window.frame.contains(pointer) {
            let carriesTabs = model.drag?.covered.contains { item in
                guard case .tab = item else { return false }
                return true
            } == true
            let leaving = coordinator.aimWindowDrag(at: carriesTabs ? pointer : nil) && carriesTabs
            if model.isLeaving != leaving {
                model.isLeaving = leaving
            }
            if newFolderDrop.isArmed {
                newFolderDrop.isArmed = false
            }
            if pinDrop.isArmed {
                pinDrop.isArmed = false
            }
            if model.target != nil {
                model.target = nil
            }
            rest()
            settleSpaceSpring()
            return
        }
        coordinator.aimWindowDrag(at: nil)
        if model.isLeaving {
            model.isLeaving = false
        }

        let inWindow = CGPoint(x: value.location.x + listOrigin.x, y: value.location.y + listOrigin.y)
        let overButton = newFolderDrop.frame.contains(inWindow)
        if overButton != newFolderDrop.isArmed {
            withAnimation(Theme.Motion.quick) { newFolderDrop.isArmed = overButton }
        }
        let overShelf = !overButton && model.acceptsPin && pinDrop.frame.contains(inWindow)
        if overShelf != pinDrop.isArmed {
            withAnimation(Theme.Motion.quick) { pinDrop.isArmed = overShelf }
        }
        guard !overButton, !overShelf else {
            rest()
            return
        }

        let onPage = model.pageOwns(inWindow)
        if onPage, model.carriedTabID != nil {
            model.aim(at: inWindow)
        } else if model.target != nil {
            model.target = nil
        }
        guard !onPage else {
            rest()
            return
        }

        if springSpace(at: inWindow) {
            rest()
            return
        }

        if drag != nil {
            react(at: value.location, in: slots)
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        defer {
            rest()
            newFolderDrop.isArmed = false
            pinDrop.isArmed = false
            for id in reopening {
                browser.folder(id: id)?.isExpanded = true
            }
            reopening = []
            coordinator.tabPreview.endSuppression()
            coordinator.aimWindowDrag(at: nil)
            model.clearDrop()
            settleSpaceSpring()
        }
        guard let drag, !drag.landing else { return }
        let lead = drag.lead
        if let destination = coordinator.finishWindowDrag(drag.items, at: NSEvent.mouseLocation) {
            selection.clear()
            guard model.floatOrigin != nil, let slot = destination.sidebarDrag.incomingFrame,
                  destination.sidebarDrag.listViewport.intersects(slot),
                  let window = destination.nativeWindow
            else {
                model.drag = nil
                return
            }
            let arriving = drag.covered
            let list = destination.sidebarDrag.listOriginInWindow
            model.chipBrowser = destination.browser
            destination.sidebarDrag.arriving = arriving
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                model.drag?.landing = true
            }
            model.floatOrigin = CGPoint(
                x: window.frame.minX + list.x + slot.minX,
                y: window.frame.maxY - list.y - slot.minY
            )
            Task {
                try? await Task.sleep(for: .milliseconds(240))
                if destination.sidebarDrag.arriving == arriving {
                    destination.sidebarDrag.arriving = []
                }
                if model.drag?.lead == lead, model.drag?.landing == true {
                    model.drag = nil
                }
            }
            return
        }
        if model.isLeaving {
            model.isLeaving = false
        }
        var settled = false

        if model.zone != .none, let id = model.carriedTabID, let tab = browser.tab(id: id) {
            coordinator.dropOnPage(tab, onto: model.targetPaneID, zone: model.zone)
            selection.clear()
        } else if newFolderDrop.isArmed {
            browser.createFolder(containing: drag.items)
            selection.clear()
            settled = true
        } else if pinDrop.isArmed {
            browser.pinAtTop(drag.items)
            settled = true
        }

        if !settled {
            browser.setPinned(pinsCarried, for: drag.items)
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            model.drag?.landing = true
        }
        if model.floatOrigin != nil, let window = coordinator.nativeWindow {
            let row = model.frames[lead] ?? drag.origin
            model.floatOrigin = CGPoint(
                x: window.frame.minX + listOrigin.x + drag.origin.minX,
                y: window.frame.maxY - listOrigin.y - row.minY
            )
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
        spring(under: point, in: slots)

        guard let hit = slots.first(where: {
            !drag.carries($0.key) && $0.value.minY <= point.y && point.y < $0.value.maxY
        }) else {
            if let lowest = slots.values.map(\.maxY).max(), point.y > lowest {
                pinsCarried = false
                browser.move(drag.items, into: nil, before: nil)
            }
            return
        }
        let before = SidebarDropGeometry.band(y: point.y, in: hit.value) == .before

        if !before, case .folder(let id) = hit.key, let folder = browser.folder(id: id),
           folder.isExpanded, browser.sidebarTree.canHold(id, drag.items) {
            pinsCarried = keepsSection(hit.key)
            browser.move(
                drag.items,
                into: folder,
                before: browser.rows(in: folder).first { !drag.carries($0) },
                settlingPins: false
            )
            return
        }

        pinsCarried = lands(before: before, of: hit.key)
        place(drag.items, before: before, of: hit.key)
    }

    private func keepsSection(_ item: SidebarItem) -> Bool {
        browser.isKept(item, ignoring: drag?.covered ?? [])
    }

    private func lands(before isBefore: Bool, of anchor: SidebarItem) -> Bool {
        guard browser.sidebarTree.parent(of: anchor) == nil else { return keeps(anchor) }
        return plan.lands(before: isBefore, of: anchor)
    }

    private func keeps(_ anchor: SidebarItem) -> Bool {
        guard let parent = browser.sidebarTree.parent(of: anchor) else {
            return keepsSection(anchor)
        }
        return keepsSection(.folder(parent))
    }

    private func place(_ items: [SidebarItem], before: Bool, of anchor: SidebarItem) {
        let tree = browser.sidebarTree
        let home = tree.parent(of: anchor)
        let siblings = tree.rows(in: home)
        guard let index = siblings.firstIndex(of: anchor) else { return }
        let target: SidebarItem? = before
            ? anchor
            : (index + 1 < siblings.endIndex ? siblings[index + 1] : nil)
        browser.move(
            items,
            into: home.flatMap(browser.folder(id:)),
            before: target,
            settlingPins: false
        )
    }

    private func spring(under point: CGPoint, in slots: [SidebarItem: CGRect]) {
        let target = shut(under: point, in: slots)
        guard target != dwelling else { return }
        dwell?.cancel()
        dwelling = target
        guard let target else {
            dwell = nil
            return
        }
        dwell = Task {
            try? await Task.sleep(for: SpringLoad.dwell)
            guard !Task.isCancelled else { return }
            browser.folder(id: target)?.isExpanded = true
            dwelling = nil
            dwell = nil
        }
    }

    private func springSpace(at point: CGPoint) -> Bool {
        guard let id = model.spaceDot(at: point) else {
            settleSpaceSpring()
            return false
        }
        guard id != model.springSpaceID else { return true }
        spaceDwell?.cancel()
        spaceDwell = nil
        guard let space = coordinator.spaceStore.space(id: id), space.id != browser.currentSpaceID,
              space.profileID == coordinator.profiles.current.id
        else {
            model.springSpaceID = nil
            return true
        }
        model.springSpaceID = id
        spaceDwell = Task {
            try? await Task.sleep(for: SpringLoad.spaceDwell)
            guard !Task.isCancelled, model.springSpaceID == id, let drag = model.drag, !drag.landing,
                  !coordinator.spaceSlider.isLanding
            else {
                model.springSpaceID = nil
                return
            }
            spaceDwell = nil
            coordinator.moveToSpace(drag.items, space: space)
            coordinator.switchSpace(to: space)
        }
        return true
    }

    private func settleSpaceSpring() {
        spaceDwell?.cancel()
        spaceDwell = nil
        if model.springSpaceID != nil {
            model.springSpaceID = nil
        }
    }

    private func rest() {
        dwell?.cancel()
        dwell = nil
        dwelling = nil
    }

    private func shut(under point: CGPoint, in slots: [SidebarItem: CGRect]) -> UUID? {
        guard case .folder(let id)? = row(under: point, in: slots),
              browser.folder(id: id)?.isExpanded == false
        else { return nil }
        return id
    }

    private func row(under point: CGPoint, in slots: [SidebarItem: CGRect]) -> SidebarItem? {
        slots.first { item, frame in
            drag?.carries(item) != true && point.y >= frame.minY && point.y < frame.maxY
        }?.key
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
