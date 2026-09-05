// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private enum WorkspaceListCoordinateSpace {
    static let name = "sidebar-workspace"
}

private enum SpringLoad {
    static let dwell: Duration = .milliseconds(250)
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
    @State private var reopening: [UUID] = []
    @State private var dwelling: UUID?
    @State private var dwell: Task<Void, Never>?

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
            pinsCarried: pinsCarried,
            space: WorkspaceListCoordinateSpace.name,
            frames: frames
        )
    }

    @ViewBuilder
    private var emptySpaceMenu: some View {
        Button {
            _ = coordinator.openNewTab()
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
                    SidebarRows(items: sections.kept, depth: 0, context: context)
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
        .contextMenu { emptySpaceMenu }
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
        frames.live(
            tabIDs: Set(browser.tabs.map(\.id)).subtracting(browser.hiddenSidebarTabIDs),
            folderIDs: Set(browser.folders.map(\.id))
        )
        .filter { item, _ in isShowing(item) }
    }

    private func isShowing(_ item: SidebarItem) -> Bool {
        var parent = browser.sidebarTree.parent(of: item)
        while let id = parent {
            guard browser.folder(id: id)?.isExpanded == true else { return false }
            parent = browser.sidebarTree.parent(of: .folder(id))
        }
        return true
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

        if model.carriedTabID != nil, model.dropFrameInWindow.contains(inWindow) {
            model.aim(at: inWindow)
        } else if model.target != nil {
            model.target = nil
        }
        guard !model.contentFrameInWindow.contains(inWindow) else {
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
            model.clearDrop()
        }
        guard let drag, !drag.landing else { return }
        let lead = drag.lead
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
    @Environment(\.windowColorScheme) private var windowColorScheme

    private var glass: Glass {
        .clear.tint(Theme.controlSurface.opacity(SidebarDragGhost.chipFillOpacity))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        content
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(glass, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
            .environment(\.colorScheme, windowColorScheme)
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
