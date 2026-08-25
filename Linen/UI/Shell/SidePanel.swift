// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

nonisolated enum SidePanelKind: String, CaseIterable, Sendable {
    case activity
    case lyrics

    var title: LocalizedStringResource {
        switch self {
        case .activity:
            "Assistant"
        case .lyrics:
            "Lyrics"
        }
    }

    var symbol: String {
        switch self {
        case .activity:
            "sparkle"
        case .lyrics:
            "quote.bubble"
        }
    }

    var isRepeatable: Bool {
        false
    }

    var usesImmersiveBackdrop: Bool {
        self == .lyrics
    }
}

nonisolated struct SidePanelTab: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: SidePanelKind

    init(id: UUID = UUID(), kind: SidePanelKind) {
        self.id = id
        self.kind = kind
    }
}

nonisolated enum SidePanelMetrics {
    static let minWidth: CGFloat = 300
    static let defaultWidth: CGFloat = minWidth
    static let maxWidth: CGFloat = 620
    static let pageMinWidth: CGFloat = 420
    static let controlInset: CGFloat = LoomChrome.canvasInset

    static let headerHeight: CGFloat = 28 + controlInset * 2
    static let tabHeight: CGFloat = 24

    static let tabInset: CGFloat = (headerHeight - tabHeight) / 2

    static func clampWidth(_ width: CGFloat, available: CGFloat) -> CGFloat {
        let ceiling = available > 0
            ? max(minWidth, min(maxWidth, available - pageMinWidth))
            : maxWidth
        return min(max(width, minWidth), ceiling)
    }
}

@MainActor
@Observable
final class SidePanelModel {
    private enum Key {
        static let visible = "sidePanel.visible"
        static let width = "sidePanel.width"
        static let expanded = "sidePanel.expanded"
        static let selected = "sidePanel.selected"
    }

    var tabs: [SidePanelTab] {
        allTabs.filter { !hidden.contains($0.kind) }
    }

    private(set) var hidden: Set<SidePanelKind> = []

    private(set) var selection: UUID?
    private(set) var isVisible: Bool {
        didSet { if isVisible != oldValue { onFootprintChange?() } }
    }
    private(set) var width: CGFloat {
        didSet { if width != oldValue { onFootprintChange?() } }
    }
    private(set) var dragWidth: CGFloat? {
        didSet { if dragWidth != oldValue { onFootprintChange?() } }
    }

    var isExpanded: Bool {
        didSet {
            guard isExpanded != oldValue else { return }
            defaults.set(isExpanded, forKey: Key.expanded)
            onFootprintChange?()
        }
    }

    @ObservationIgnored var onFootprintChange: (() -> Void)?

    @ObservationIgnored private let allTabs: [SidePanelTab]
    @ObservationIgnored private var dragOrigin: CGFloat?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let all = SidePanelKind.allCases.map { SidePanelTab(kind: $0) }
        let chosen = defaults.string(forKey: Key.selected)
            .flatMap(SidePanelKind.init(rawValue:))
            .flatMap { kind in all.first { $0.kind == kind }?.id }
        allTabs = all
        selection = chosen
        isVisible = (defaults.object(forKey: Key.visible) as? Bool ?? false) && chosen != nil
        isExpanded = defaults.bool(forKey: Key.expanded)
        let savedWidth = defaults.double(forKey: Key.width)
        width = savedWidth > 0 ? CGFloat(savedWidth) : SidePanelMetrics.defaultWidth
    }

    // MARK: - What is on screen

    var selected: SidePanelTab? {
        tabs.first { $0.id == selection }
    }

    var selectedKind: SidePanelKind? {
        selected?.kind
    }

    func isShowing(_ kind: SidePanelKind) -> Bool {
        isVisible && selectedKind == kind
    }

    // MARK: - Opening and closing

    func show(_ kind: SidePanelKind) {
        guard let tab = tabs.first(where: { $0.kind == kind }) else { return }
        selection = tab.id
        isVisible = true
        persist()
    }

    func show(seeding kind: SidePanelKind) {
        if selection == nil {
            selection = tabs.first { $0.kind == kind }?.id ?? tabs.first?.id
        }
        guard selection != nil else { return }
        isVisible = true
        persist()
    }

    func toggleVisibility(seeding kind: SidePanelKind) {
        if isVisible {
            hide()
        } else {
            show(seeding: kind)
        }
    }

    func setAvailable(_ isAvailable: Bool, for kind: SidePanelKind) {
        let next = isAvailable ? hidden.subtracting([kind]) : hidden.union([kind])
        guard next != hidden else { return }
        let wasSelected = selectedKind == kind
        hidden = next
        guard !isAvailable, wasSelected else { return }
        selection = tabs.first?.id
        isVisible = isVisible && selection != nil
        persist()
    }

    func toggle(_ kind: SidePanelKind) {
        if isShowing(kind) {
            hide()
        } else {
            show(kind)
        }
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selection = id
        isVisible = true
        persist()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        persist()
    }

    @discardableResult
    func close() -> Bool {
        guard isVisible else { return false }
        hide()
        return true
    }

    private func persist() {
        defaults.set(selectedKind?.rawValue, forKey: Key.selected)
        defaults.set(isVisible, forKey: Key.visible)
    }

    // MARK: - Width

    func openWidth(in available: CGFloat) -> CGFloat {
        if let dragWidth {
            return dragWidth
        }
        return SidePanelMetrics.clampWidth(width, available: available)
    }

    var isDragging: Bool {
        dragOrigin != nil
    }

    func dragChanged(translation: CGFloat, available: CGFloat) {
        if dragOrigin == nil {
            dragOrigin = openWidth(in: available)
        }
        apply((dragOrigin ?? 0) - translation, releasing: false, available: available)
    }

    func dragEnded(translation: CGFloat, available: CGFloat) {
        apply((dragOrigin ?? openWidth(in: available)) - translation, releasing: true, available: available)
        dragOrigin = nil
        dragWidth = nil
        persistWidth()
    }

    func resetWidth() {
        width = SidePanelMetrics.defaultWidth
        dragWidth = nil
        persistWidth()
    }

    private func apply(_ proposed: CGFloat, releasing: Bool, available: CGFloat) {
        let live = SidePanelMetrics.clampWidth(proposed, available: available)
        if !releasing {
            dragWidth = live
            return
        }
        width = live
        dragWidth = live
    }

    private func persistWidth() {
        defaults.set(Double(width), forKey: Key.width)
    }
}
