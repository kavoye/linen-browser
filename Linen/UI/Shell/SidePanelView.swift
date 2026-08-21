// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SidePanelSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let containerWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    var body: some View {
        VStack(spacing: 0) {
            SidePanelHeader(coordinator: coordinator)
            content
        }
        .background {
            ZStack {
                if panel.selectedKind?.paintsThePanel == true {
                    LyricsBackdrop(artwork: coordinator.lyricsSource.artworkURL)
                } else {
                    VisualEffectView(material: .sidebar)
                    Theme.sidebarTint.opacity(0.55)
                }
                WindowDragArea()
            }
        }
        .colorScheme(panel.selectedKind?.paintsThePanel == true ? .dark : colorScheme)
        .overlay(alignment: .leading) {
            if !panel.isExpanded {
                ColumnEdgeHandle(
                    edge: .leading,
                    grabWidth: SidePanelMetrics.grabWidth,
                    isDragging: panel.isDragging,
                    onDragChanged: { panel.dragChanged(translation: $0, container: containerWidth) },
                    onDragEnded: { panel.dragEnded(translation: $0, container: containerWidth) },
                    onReset: { panel.resetWidth() }
                )
            }
        }
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

            QuietIconButton(
                symbol: "xmark",
                isOn: false,
                help: String(localized: "Hide Side Panel")
            ) {
                panel.hide()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: SidePanelMetrics.headerHeight)
    }
}

struct SidePanelToggle: View {
    let coordinator: AppCoordinator

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    /// One mark at a time: what the panel would show you right now. The agent
    /// outranks the music, because only the agent's mark can mean "look at this".
    private var status: SidePanelStatus? {
        if let mark = coordinator.agentMark {
            return .agent(mark)
        }
        return coordinator.showsLyrics ? .lyrics : nil
    }

    var body: some View {
        if !panel.isVisible {
            ToolbarButton(
                symbol: "sidebar.right",
                enabled: true,
                help: String(localized: "Show Side Panel (⌥⌘A)")
            ) {
                panel.show(seeding: coordinator.showsLyrics ? .lyrics : .activity)
            }
            .overlay(alignment: .topTrailing) {
                SidePanelStatusMark(status: status)
                    .frame(width: 12, height: 12)
                    .offset(x: -3, y: 3)
                    .allowsHitTesting(false)
            }
        }
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
        case let .agent(dot):
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

    private var background: Color {
        if isSelected {
            return Theme.Wash.selection
        }
        return hovering ? Theme.Wash.hover : Theme.Wash.none
    }

    var body: some View {
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
        .background(background, in: .rect(cornerRadius: Theme.Radius.chip))
        .contentShape(.rect(cornerRadius: Theme.Radius.chip))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
