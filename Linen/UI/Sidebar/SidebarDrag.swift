// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SidebarDrag {
    let items: [SidebarItem]
    let lead: SidebarItem
    let origin: CGRect
    let covered: Set<SidebarItem>
    var translation: CGSize = .zero
    var landing = false

    init(items: [SidebarItem], lead: SidebarItem, origin: CGRect, tree: SidebarTree) {
        self.items = items
        self.lead = lead
        self.origin = origin
        covered = tree.expanded(Set(items))
    }

    var isSingle: Bool {
        items.count == 1
    }

    var carriesFolder: Bool {
        items.contains { if case .folder = $0 { true } else { false } }
    }

    func carries(_ item: SidebarItem) -> Bool {
        covered.contains(item)
    }
}

enum SidebarDragGhost {
    static func liftScale(style: SidebarStyle) -> CGFloat {
        style == .icons ? 1 : 1.03
    }

    static let chipFillOpacity: Double = 0.55
}

nonisolated enum SidebarDropIntent: Equatable {
    case fold(SidebarItem)
    case split(SidebarItem, leading: Bool)

    var item: SidebarItem {
        switch self {
        case .fold(let item):
            item
        case .split(let item, _):
            item
        }
    }

    var isFold: Bool {
        if case .fold = self {
            true
        } else {
            false
        }
    }
}

@MainActor
@Observable
final class SidebarDragModel {
    var drag: SidebarDrag?

    let frames = SidebarFrames()

    var listOriginInWindow: CGPoint = .zero

    var contentFrameInWindow: CGRect = .zero

    var dropFrameInWindow: CGRect {
        contentFrameInWindow
    }

    var dropPlan: SplitDropPlan {
        planSource?() ?? SplitDropPlan()
    }

    @ObservationIgnored var planSource: (() -> SplitDropPlan)?

    var target: SplitDropPlan.Target?

    var zone: SplitDropZone {
        target?.edge ?? .none
    }
    var targetPaneID: UUID? {
        target?.anchor
    }

    func aim(at pointInWindow: CGPoint) {
        let origin = contentFrameInWindow.origin
        let local = CGPoint(
            x: pointInWindow.x - origin.x,
            y: pointInWindow.y - origin.y
        )
        let next = dropPlan.target(at: local)
        guard next != target else { return }
        target = next
    }

    func clearDrop() {
        target = nil
        source = .none
    }

    var source: PageDropSource = .none

    var panePointInWindow: CGPoint = .zero

    var carriedPaneID: UUID? {
        guard case .pane(let id) = source else { return nil }
        return id
    }

    enum PageDropSource: Equatable {
        case none
        case row
        case pane(UUID)
    }

    var carriedTabID: UUID? {
        guard let drag, drag.items.count == 1, case .tab(let id) = drag.lead else { return nil }
        return id
    }
}

@MainActor
final class SidebarFrames {
    private var slots: [SidebarItem: CGRect] = [:]

    func record(_ item: SidebarItem, at frame: CGRect) {
        slots[item] = frame
    }

    subscript(item: SidebarItem) -> CGRect? {
        slots[item]
    }

    func live(tabIDs: Set<UUID>, folderIDs: Set<UUID>) -> [SidebarItem: CGRect] {
        slots.filter { entry in
            switch entry.key {
            case .tab(let id):
                tabIDs.contains(id)
            case .folder(let id):
                folderIDs.contains(id)
            }
        }
    }
}

struct SidebarRowContext {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let selection: SidebarSelection
    let drag: SidebarDrag?
    let armed: SidebarDropIntent?
    let candidate: SidebarDropIntent?
    let offersSplit: Bool
    let space: String
    let frames: SidebarFrames

    var refractsTabColor: Bool {
        coordinator.settings.refractsTabColor
    }

    func isLifted(_ item: SidebarItem) -> Bool {
        drag?.items.contains(item) == true
    }

    func isArmed(_ item: SidebarItem) -> Bool {
        armed == .fold(item)
    }

    func isFoldCandidate(_ item: SidebarItem) -> Bool {
        candidate == .fold(item) && armed != .fold(item)
    }

    func armedSplitEdge(_ item: SidebarItem) -> HorizontalEdge? {
        guard case .split(let target, let leading) = armed, target == item else { return nil }
        return leading ? .leading : .trailing
    }

    func candidateSplitEdge(_ item: SidebarItem) -> HorizontalEdge? {
        guard case .split(let target, let leading) = candidate, target == item else { return nil }
        return leading ? .leading : .trailing
    }

    func showsSplitEdges(_ item: SidebarItem) -> Bool {
        Self.showsSplitEdges(offersSplit: offersSplit, item: item, candidate: candidate, armed: armed)
    }

    static func showsSplitEdges(
        offersSplit: Bool,
        item: SidebarItem,
        candidate: SidebarDropIntent?,
        armed: SidebarDropIntent?
    ) -> Bool {
        offersSplit && (candidate?.item == item || armed?.item == item)
    }
    func isSelected(_ item: SidebarItem) -> Bool {
        selection.contains(item)
    }

    var activeItem: SidebarItem? {
        guard case .tab(let id) = coordinator.sidebarDestination else { return nil }
        return .tab(browser.splits.split(containing: id)?.leader ?? id)
    }
}

struct SidebarRows: View {
    let items: [SidebarItem]
    let depth: Int
    let context: SidebarRowContext

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .folder(let id):
                if let folder = context.browser.folder(id: id) {
                    FolderSection(folder: folder, depth: depth, context: context)
                }
            case .tab(let id):
                if let tab = context.browser.tab(id: id) {
                    if context.browser.splits.isFollower(id) {
                        EmptyView()
                    } else if let grid = context.browser.splits.splitLed(by: id) {
                        SidebarSplitRow(leading: tab, split: grid, depth: depth, context: context)
                    } else {
                        SidebarTabRow(tab: tab, depth: depth, context: context)
                    }
                }
            }
        }
    }
}
