// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

enum InspectorMetrics {
    static let defaultWidth: CGFloat = 268
    static let minWidth: CGFloat = defaultWidth
    static let maxWidth: CGFloat = 520
    static let maxWindowFraction: CGFloat = 0.45
    static let grabWidth: CGFloat = 8

    static func clampWidth(_ width: CGFloat, container: CGFloat) -> CGFloat {
        let ceiling = container > 0
            ? max(minWidth, min(maxWidth, container * maxWindowFraction))
            : maxWidth
        return min(max(width, minWidth), ceiling)
    }
}

@MainActor
@Observable
final class InspectorLayout {
    private enum Key {
        static let visible = "inspector.visible"
        static let width = "inspector.width"
    }

    var isVisible: Bool {
        didSet {
            guard isVisible != oldValue else { return }
            defaults.set(isVisible, forKey: Key.visible)
        }
    }

    private(set) var width: CGFloat
    private(set) var dragWidth: CGFloat?

    private(set) var seenFailureCount = 0

    private var dragOrigin: CGFloat?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = defaults.object(forKey: Key.visible) as? Bool ?? false
        let stored = defaults.double(forKey: Key.width)
        width = stored > 0 ? CGFloat(stored) : InspectorMetrics.defaultWidth
    }

    var isDragging: Bool {
        dragOrigin != nil
    }

    func openWidth(in container: CGFloat) -> CGFloat {
        if let dragWidth {
            return dragWidth
        }
        return InspectorMetrics.clampWidth(width, container: container)
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
    }

    func toggle() {
        isVisible.toggle()
    }

    @discardableResult
    func close() -> Bool {
        guard isVisible else { return false }
        isVisible = false
        return true
    }

    func resetWidth() {
        width = InspectorMetrics.defaultWidth
        dragWidth = nil
        persistWidth()
    }

    func reviewFailures(_ count: Int) {
        guard isVisible else { return }
        seenFailureCount = max(seenFailureCount, count)
    }

    func needsAttention(failureCount: Int) -> Bool {
        !isVisible && failureCount > seenFailureCount
    }

    // MARK: - Drag

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

    private func apply(_ proposed: CGFloat, releasing: Bool, container: CGFloat) {
        let live = InspectorMetrics.clampWidth(proposed, container: container)

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

enum AgentActivityDot {
    enum State {
        case working
        case attention
    }

    static func state(isWorking: Bool, needsAttention: Bool) -> State? {
        if needsAttention {
            return .attention
        }
        return isWorking ? .working : nil
    }
}

struct AgentInspector: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let layout: InspectorLayout
    let containerWidth: CGFloat

    @Environment(\.windowControlsInset) private var windowControlsInset

    private var activeTabID: UUID? {
        browser.activeTab?.id
    }

    private var activeSpaceID: UUID? {
        browser.activeSpaceID
    }

    private var isRunning: Bool {
        traces.last?.state == .running
    }

    private var traces: [ConversationLog.TaskTrace] {
        guard let activeSpaceID else { return [] }
        return coordinator.conversationLog.traces(forTab: activeSpaceID)
    }

    private var usage: ConversationLog.Usage {
        guard let activeSpaceID else { return .zero }
        return coordinator.conversationLog.usage(forTab: activeSpaceID)
    }

    private var topPadding: CGFloat {
        windowControlsInset > 0 ? 8 : 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorTopRow(
                layout: layout,
                isRunning: isRunning,
                pageCount: browser.activeSplit?.count ?? 1
            )
            .padding(.horizontal, 12)

            ResearchGlimpse(preview: coordinator.researchPreview, activeSpaceID: activeSpaceID)
                .padding(.horizontal, 12)

            if let activeTabID {
                AgentActivityPanel(
                    traces: traces,
                    tabID: activeTabID,
                    browser: browser,
                    onRetry: { prompt in
                        Task { await coordinator.handleTypedUtterance(prompt) }
                    }
                )
            } else {
                Spacer(minLength: 0)
            }

            InspectorFooter(coordinator: coordinator, usage: usage)
                .padding(.horizontal, 12)
        }
        .padding(.top, topPadding)
        .padding(.bottom, 12)
        .onChange(of: layout.isVisible, initial: true) { _, _ in
            layout.reviewFailures(coordinator.conversationLog.failureCount)
        }
        .onChange(of: coordinator.conversationLog.failureCount) { _, count in
            layout.reviewFailures(count)
        }
        .background {
            ZStack(alignment: .leading) {
                VisualEffectView(material: .sidebar)
                Theme.sidebarTint.opacity(0.55)
                WindowDragArea()
                InspectorDivider(layout: layout, containerWidth: containerWidth)
            }
        }
    }
}

private struct ResearchGlimpse: View {
    let preview: ResearchPreview
    let activeSpaceID: UUID?

    var body: some View {
        if let snapshot = preview.snapshot, preview.spaceID == activeSpaceID {
            VStack(alignment: .leading, spacing: 5) {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.Wash.selection, lineWidth: 1)
                    )
                    .opacity(preview.isLive ? 1 : 0.55)

                HStack(spacing: 5) {
                    Circle()
                        .fill(preview.isLive ? Theme.accent : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(caption)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            .transition(.opacity)
            .animation(Theme.Motion.settle, value: preview.isLive)
        }
    }

    private var caption: LocalizedStringResource {
        let place = preview.host ?? String(localized: "the research page")
        let caption: LocalizedStringResource = preview.isLive
            ? "Browsing \(place)…"
            : "Finished on \(place)"
        return caption
    }
}

private struct InspectorTopRow: View {
    let layout: InspectorLayout
    let isRunning: Bool
    let pageCount: Int

    private var title: LocalizedStringResource {
        if pageCount > 1 {
            return isRunning ? "Working on these pages" : "Activity on these pages"
        }
        return isRunning ? "Working on this tab" : "Activity on this tab"
    }

    var body: some View {
        HStack(spacing: 6) {
            AgentStateMarker(isRunning: isRunning)
                .frame(width: 12)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            QuietIconButton(symbol: "sidebar.right", isOn: false, help: String(localized: "Hide Agent Activity (⌥⌘A)")) {
                layout.toggle()
            }
        }
        .padding(.bottom, 2)
    }
}

private struct InspectorFooter: View {
    let coordinator: AppCoordinator
    let usage: ConversationLog.Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModelChip(coordinator: coordinator)

            if usage.requestCount > 0 {
                AgentUsageSummary(usage: usage)
                    .padding(.leading, ModelChipMetrics.textInset)
            }

            Text(AIDisclosure.replyCaption)
                .font(Theme.Font.micro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 2)
        }
    }
}

private struct InspectorDivider: View {
    let layout: InspectorLayout
    let containerWidth: CGFloat

    var body: some View {
        ColumnEdgeHandle(
            edge: .leading,
            grabWidth: InspectorMetrics.grabWidth,
            isDragging: layout.isDragging,
            onDragChanged: { layout.dragChanged(translation: $0, container: containerWidth) },
            onDragEnded: { layout.dragEnded(translation: $0, container: containerWidth) },
            onReset: { layout.resetWidth() }
        )
    }
}
