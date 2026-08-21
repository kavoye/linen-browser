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
            "Activity"
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

    /// A repeatable kind opens a new tab every time. Nothing is repeatable yet;
    /// a chat would be.
    var isRepeatable: Bool {
        false
    }

    /// Whether this kind paints the whole panel, tab strip included, and so
    /// carries its own idea of what the chrome sits on.
    var paintsThePanel: Bool {
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
    static let maxWindowFraction: CGFloat = 0.5
    static let grabWidth: CGFloat = 8
    static let headerHeight: CGFloat = 34

    static func clampWidth(_ width: CGFloat, container: CGFloat) -> CGFloat {
        let ceiling = container > 0
            ? max(minWidth, min(maxWidth, container * maxWindowFraction))
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

    /// Every kind a setting allows has a tab, always. Nothing is added or
    /// closed yet; a repeatable kind is what would make this list move.
    var tabs: [SidePanelTab] {
        allTabs.filter { !hidden.contains($0.kind) }
    }

    /// A kind turned off in Settings has no tab, so the panel cannot land on it.
    private(set) var hidden: Set<SidePanelKind> = []

    /// Nil until the panel has been opened once, which is what lets the first
    /// open land on whatever the toolbar button was marked for.
    private(set) var selection: UUID?
    private(set) var isVisible: Bool
    private(set) var width: CGFloat
    private(set) var dragWidth: CGFloat?

    var isExpanded: Bool {
        didSet {
            guard isExpanded != oldValue else { return }
            defaults.set(isExpanded, forKey: Key.expanded)
        }
    }

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

    /// The panel's own button reopens whatever was last in it, and only picks a
    /// kind when there is nothing to come back to.
    func show(seeding kind: SidePanelKind) {
        if selection == nil {
            selection = tabs.first { $0.kind == kind }?.id ?? tabs.first?.id
        }
        guard selection != nil else { return }
        isVisible = true
        persist()
    }

    /// Turning a kind off takes its tab away, and the panel steps off it.
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

    /// Leaves the selection where it is, so reopening brings back the same tab.
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

    func openWidth(in container: CGFloat) -> CGFloat {
        if let dragWidth {
            return dragWidth
        }
        return SidePanelMetrics.clampWidth(width, container: container)
    }

    var isDragging: Bool {
        dragOrigin != nil
    }

    func dragChanged(translation: CGFloat, container: CGFloat) {
        if dragOrigin == nil {
            dragOrigin = openWidth(in: container)
        }
        apply((dragOrigin ?? 0) - translation, releasing: false, container: container)
    }

    func dragEnded(translation: CGFloat, container: CGFloat) {
        apply((dragOrigin ?? openWidth(in: container)) - translation, releasing: true, container: container)
        dragOrigin = nil
        dragWidth = nil
        persistWidth()
    }

    func resetWidth() {
        width = SidePanelMetrics.defaultWidth
        dragWidth = nil
        persistWidth()
    }

    private func apply(_ proposed: CGFloat, releasing: Bool, container: CGFloat) {
        let live = SidePanelMetrics.clampWidth(proposed, container: container)
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
