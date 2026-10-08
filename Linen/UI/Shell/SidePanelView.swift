// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension AppCoordinator {
    func isAdded(_ kind: SidePanelKind) -> Bool {
        switch kind {
        case .activity:
            true
        case .lyrics:
            settings.showsLyrics
        case .github:
            settings.showsGitHub
        case .watches:
            !browser.context.pageWatches.watches.isEmpty
        }
    }

    func setAdded(_ isAdded: Bool, _ kind: SidePanelKind) {
        switch kind {
        case .activity, .watches:
            return
        case .lyrics:
            settings.showsLyrics = isAdded
        case .github:
            settings.showsGitHub = isAdded
        }
        if isAdded {
            sidePanel.show(kind)
        }
    }
}

struct SidePanelSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var panel: SidePanelModel {
        coordinator.sidePanel
    }

    var body: some View {
        let shape = LoomChrome.canvasShape
        let wash = panelWash
        ZStack {
            if panel.selectedKind?.usesImmersiveBackdrop == true {
                LyricsBackdrop(artwork: coordinator.lyricsSource.artworkURL)
            } else {
                if coordinator.settings.hasSolidSidePanel {
                    shape.fill(Theme.windowBackground)
                } else {
                    LoomPanelFill(shape: shape)
                }

                if panel.selectedKind == .activity, coordinator.isVoiceConversationPresented {
                    VoiceConversationBackdrop(session: coordinator.conversationVoice)
                        .transition(.opacity)
                } else if panel.selectedKind == .activity, panel.isExpanded {
                    AssistantExpandedBackdrop()
                }
            }

            SidePanelInteractionBoundary()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                SidePanelHeader(coordinator: coordinator)
                content
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.55), value: coordinator.isVoiceConversationPresented)
        .contentShape(shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .environment(\.chromeIsLight, wash.isLight)
        .environment(\.chromeWash, wash)
        .environment(\.colorScheme, wash.isLight ? .light : .dark)
    }

    private var panelWash: ChromeWash {
        if panel.selectedKind?.usesImmersiveBackdrop == true {
            return .of(nil, isLight: false)
        }
        if coordinator.settings.hasSolidSidePanel {
            return .of(nil, isLight: colorScheme == .light)
        }
        return ChromeBand.loomWash(browser: browser, coordinator: coordinator, scheme: colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch panel.selectedKind {
        case .activity:
            AgentInspector(browser: browser, coordinator: coordinator)
        case .lyrics:
            LyricsSurface(coordinator: coordinator)
        case .github:
            GitHubPanelSurface(browser: browser, coordinator: coordinator)
        case .watches:
            WatchesPanelSurface(center: browser.context.pageWatches, coordinator: coordinator)
        case nil:
            Spacer(minLength: 0)
        }
    }
}

private struct AssistantExpandedBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.windowBackground.opacity(reduceTransparency ? 1 : 0.65), location: 0),
                .init(color: Theme.windowBackground.opacity(reduceTransparency ? 1 : 0.78), location: 0.65),
                .init(color: Theme.windowBackground.opacity(reduceTransparency ? 1 : 0.94), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Block clicks through empty panel regions while allowing controls in front
/// to handle their own input.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    count: tab.kind == .github ? coordinator.github.notifications.count : 0,
                    onSelect: { panel.select(tab.id) },
                    onRemove: tab.kind.isRemovable ? { coordinator.setAdded(false, tab.kind) } : nil
                )
            }

            SidePanelAddMenu(coordinator: coordinator)

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
        .padding(.horizontal, SidePanelMetrics.tabInset)
        .frame(height: SidePanelMetrics.headerHeight)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.18), value: panel.selection)
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
        if !coordinator.github.notifications.isEmpty {
            return .github
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
                    ? "Hide Side Panel (⌥⌘S)"
                    : "Show Side Panel (⌥⌘S)"
            )
        ) {
            coordinator.toggleSidePanel()
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
    case github
}

private struct SidePanelStatusMark: View {
    let status: SidePanelStatus?

    var body: some View {
        switch status {
        case .agent(.attention):
            AgentStateMarker(isRunning: true, tint: Theme.warning)
        case .agent(.working):
            ComposingOrb(size: 16)
        case .lyrics:
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.accent)
        case .github:
            Circle()
                .fill(Theme.accent)
                .frame(width: 7, height: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 1, y: -1)
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

private struct SidePanelAddMenu: View {
    let coordinator: AppCoordinator

    @State private var hovering = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering || isPresented ? .primary : .secondary)
                .hoverLift(hovering)
                .frame(width: 28, height: SidePanelMetrics.tabHeight)
                .selectionBackground(isSelected: isPresented, isHovering: false, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SidePanelGallery(coordinator: coordinator) { isPresented = false }
                .chromePopoverAppearance()
        }
        .help(Text("Add to Side Panel"))
        .accessibilityLabel(Text("Add to Side Panel"))
    }
}

private struct SidePanelGallery: View {
    let coordinator: AppCoordinator
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Side Panel")
                .font(.system(size: 13, weight: .semibold))

            ForEach(SidePanelKind.allCases.filter(\.isRemovable), id: \.self) { kind in
                SidePanelGalleryRow(kind: kind, isAdded: coordinator.isAdded(kind)) {
                    let adding = !coordinator.isAdded(kind)
                    coordinator.setAdded(adding, kind)
                    if adding {
                        onAdd()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct SidePanelKindIcon: View {
    let kind: SidePanelKind
    let size: CGFloat

    var body: some View {
        switch kind.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size + 1, height: size + 1)
        case .orb:
            ComposingOrb(size: size + 5, isAnimating: false)
                .frame(width: size + 1, height: size + 1)
        }
    }
}

private struct SidePanelGalleryRow: View {
    let kind: SidePanelKind
    let isAdded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SidePanelKindIcon(kind: kind, size: 14)
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .settingsSurface(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(kind.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Group {
                if isAdded {
                    SettingsButton(title: "Remove", isDestructive: true, minWidth: 72, action: onToggle)
                } else {
                    SettingsButton(title: "Add", isProminent: true, minWidth: 72, action: onToggle)
                }
            }
            .frame(height: 34)
        }
    }
}

private struct SidePanelTabChip: View {
    let tab: SidePanelTab
    let isSelected: Bool
    let mark: AgentActivityDot.State?
    let count: Int
    let onSelect: () -> Void
    let onRemove: (() -> Void)?

    @State private var hovering = false

    private var lifts: Bool {
        hovering && !isSelected
    }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 5) {
            if mark == .attention {
                AgentStateMarker(isRunning: true, tint: Theme.warning)
                    .frame(width: 11, height: 11)
            } else if tab.kind == .activity {
                ComposingOrb(size: 15, isAnimating: mark == .working)
                    .frame(width: 11, height: 11)
                    .opacity(isSelected || hovering ? 1 : 0.6)
                    .hoverLift(lifts)
            } else {
                SidePanelKindIcon(kind: tab.kind, size: 10)
                    .foregroundStyle(count > 0 ? Theme.accent : isSelected || hovering ? Color.primary : Color.secondary)
                    .hoverLift(lifts)
            }

            if isSelected {
                Text(tab.kind.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 9)
        .frame(height: SidePanelMetrics.tabHeight)
        .selectionBackground(isSelected: isSelected, isHovering: false, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .help(isSelected ? "" : String(localized: tab.kind.title))
        .contextMenu {
            if let onRemove {
                Button("Remove from Side Panel", action: onRemove)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tab.kind.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(count > 0 ? Text("\(count) loaded unread notifications") : Text(""))
    }
}
