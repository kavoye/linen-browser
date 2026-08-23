// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SidePanelSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @Environment(\.colorScheme) private var colorScheme

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    var body: some View {
        let shape = LoomChrome.canvasShape
        ZStack {
            if panel.selectedKind?.usesImmersiveBackdrop == true {
                LyricsBackdrop(artwork: coordinator.lyricsSource.artworkURL)
            } else {
                LoomPanelFill(shape: shape)
            }

            SidePanelInteractionBoundary()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                SidePanelHeader(coordinator: coordinator)
                content
            }
        }
        .contentShape(shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .colorScheme(panel.selectedKind?.usesImmersiveBackdrop == true ? .dark : colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch panel.selectedKind {
        case .activity:
            AgentInspector(browser: browser, coordinator: coordinator)
        case .lyrics:
            LyricsSurface(coordinator: coordinator)
        case nil:
            Spacer(minLength: 0)
        }
    }
}

/// A panel is an interaction boundary even where its SwiftUI content is
/// visually empty. The native view sits behind the panel's controls, so their
/// buttons and scroll views win hit testing while otherwise-empty regions no
/// longer fall through to the web view underneath.
private struct SidePanelInteractionBoundary: NSViewRepresentable {
    func makeNSView(context: Context) -> BoundaryView {
        BoundaryView()
    }

    func updateNSView(_ nsView: BoundaryView, context: Context) {}

    final class BoundaryView: NSView {
        override var acceptsFirstResponder: Bool {
            false
        }

        override func scrollWheel(with event: NSEvent) {}

        override func mouseDown(with event: NSEvent) {}

        override func rightMouseDown(with event: NSEvent) {}

        override func otherMouseDown(with event: NSEvent) {}

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }
    }
}

private struct SidePanelHeader: View {
    let coordinator: AppCoordinator

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    private var expandHelp: LocalizedStringResource {
        panel.isExpanded ? "Collapse Side Panel" : "Expand Side Panel"
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(panel.tabs) { tab in
                SidePanelTabChip(
                    tab: tab,
                    isSelected: panel.selection == tab.id,
                    mark: tab.kind == .activity ? coordinator.agentMark : nil,
                    onSelect: { panel.select(tab.id) }
                )
            }

            Spacer(minLength: 4)

            QuietIconButton(
                symbol: panel.isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                isOn: false,
                help: String(localized: expandHelp)
            ) {
                panel.isExpanded.toggle()
            }
        }
        .padding(.horizontal, SidePanelMetrics.controlInset)
        .frame(height: SidePanelMetrics.headerHeight)
    }
}

struct SidePanelToggle: View {
    let coordinator: AppCoordinator

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    private var status: SidePanelStatus? {
        if let mark = coordinator.agentMark {
            return .agent(mark)
        }
        return coordinator.hasLyrics ? .lyrics : nil
    }

    private var accessibilityLabel: LocalizedStringResource {
        panel.isVisible ? "Hide Side Panel" : "Show Side Panel"
    }

    var body: some View {
        ToolbarButton(
            symbol: "sidebar.right",
            enabled: true,
            isOn: panel.isVisible,
            highlightsWhenOn: false,
            help: String(
                localized: panel.isVisible
                    ? "Hide Side Panel (⌥⌘A)"
                    : "Show Side Panel (⌥⌘A)"
            )
        ) {
            panel.toggleVisibility(seeding: coordinator.showsLyrics ? .lyrics : .activity)
        }
        .overlay(alignment: .topTrailing) {
            if !panel.isVisible {
                SidePanelStatusMark(status: status)
                    .frame(width: 12, height: 12)
                    .offset(x: -3, y: 3)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private enum SidePanelStatus: Equatable {
    case agent(AgentActivityDot.State)
    case lyrics
}

private struct SidePanelStatusMark: View {
    let status: SidePanelStatus?

    var body: some View {
        switch status {
        case .agent(let dot):
            AgentStateMarker(
                isRunning: true,
                tint: dot == .attention ? Theme.warning : Theme.accent
            )
        case .lyrics:
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.accent)
        case nil:
            EmptyView()
        }
    }
}

struct PanelNotice: View {
    let symbol: String?
    let title: LocalizedStringResource
    var caption: LocalizedStringResource?

    var body: some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            } else {
                Spinner(size: 16)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let caption {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidePanelTabChip: View {
    let tab: SidePanelTab
    let isSelected: Bool
    let mark: AgentActivityDot.State?
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 5) {
            if let mark {
                AgentStateMarker(isRunning: true, tint: mark == .attention ? Theme.warning : Theme.accent)
                    .frame(width: 11, height: 11)
            } else {
                Image(systemName: tab.kind.symbol)
                    .font(.system(size: 10, weight: .medium))
            }

            Text(tab.kind.title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .selectionBackground(isSelected: isSelected, isHovering: hovering, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
