// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SidebarDrag {
    let items: [SidebarItem]
    let lead: SidebarItem
    let origin: CGRect
    let covered: Set<SidebarItem>
    let keepsSection: Bool
    let wasKept: Bool
    var translation: CGSize = .zero
    var landing = false

    init(
        items: [SidebarItem],
        lead: SidebarItem,
        origin: CGRect,
        tree: SidebarTree,
        keepsSection: Bool,
        wasKept: Bool
    ) {
        self.items = items
        self.lead = lead
        self.origin = origin
        self.keepsSection = keepsSection
        self.wasKept = wasKept
        covered = tree.expanded(Set(items))
    }

    var isSingle: Bool {
        items.count == 1
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

    var acceptsPin: Bool {
        guard let drag, !drag.landing else { return false }
        return !drag.keepsSection
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
    let pinsCarried: Bool
    let space: String
    let frames: SidebarFrames

    var refractsTabColor: Bool {
        coordinator.settings.refractsTabColor
    }

    func isLifted(_ item: SidebarItem) -> Bool {
        drag?.items.contains(item) == true
    }

    func dropMark(_ item: SidebarItem) -> SidebarDropMark.Kind? {
        guard let lead = drag?.lead, lead == item else { return nil }
        if pinsCarried != browser.isKept(lead) {
            return pinsCarried ? .pin : .unpin
        }
        return .move
    }

    func isSelected(_ item: SidebarItem) -> Bool {
        selection.contains(item)
    }

    var activeItem: SidebarItem? {
        guard case .tab(let id) = coordinator.sidebarDestination else { return nil }
        return .tab(browser.splits.split(containing: id)?.leader ?? id)
    }
}

enum SidebarPinMetrics {
    static let hairline = Theme.chrome(0.14)
}

struct SidebarSectionSeam: View {
    var body: some View {
        Capsule()
            .fill(SidebarPinMetrics.hairline)
            .frame(height: 1)
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: .full))
            .padding(.vertical, 3)
    }
}

struct SidebarDropMark: View {
    enum Kind {
        case move
        case pin
        case unpin
    }

    let kind: Kind
    var isArmed = false

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.windowColorScheme) private var windowColorScheme

    private static let dash: [CGFloat] = [4, 3]

    private var calls: Bool {
        kind == .pin || kind == .unpin
    }

    private var tint: Color {
        isArmed && calls ? Theme.accent : Color.primary.opacity(0.45)
    }

    private var symbol: String {
        switch kind {
        case .move:
            "arrow.up.and.down"
        case .pin:
            "pin.fill"
        case .unpin:
            "pin.slash.fill"
        }
    }

    @ViewBuilder
    private var label: some View {
        switch kind {
        case .move:
            Text("Move")
        case .pin:
            Text("Pin")
        case .unpin:
            Text("Unpin")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
        HStack(spacing: SidebarMetrics.rowIconSpacing) {
            Image(systemName: symbol)
                .font(Theme.Font.control)
                .frame(width: SidebarMetrics.rowIconSize)
            if sidebarStyle == .full {
                label
                    .font(Theme.Font.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sidebarStyle == .full ? .leading : .center)
        .background { shape.fill(Theme.accent.opacity(isArmed && calls ? 0.16 : 0)) }
        .overlay {
            shape.strokeBorder(
                tint.opacity(isArmed ? 1 : 0.5),
                style: StrokeStyle(lineWidth: 1, dash: isArmed && calls ? [] : Self.dash)
            )
        }
        .environment(\.colorScheme, windowColorScheme)
        .allowsHitTesting(false)
    }
}

struct SidebarRows: View {
    let items: [SidebarItem]
    let depth: Int
    let context: SidebarRowContext

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element) { _, item in
            row(item)
                .overlay {
                    if let mark = context.dropMark(item) {
                        SidebarDropMark(kind: mark, isArmed: true)
                    }
                }
        }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem) -> some View {
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
