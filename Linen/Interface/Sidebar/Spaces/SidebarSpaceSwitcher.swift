// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SidebarSpaceSwitcher: View {
    let coordinator: AppCoordinator
    var axis: Axis = .horizontal

    @State private var hoveredID: UUID?
    @State private var tipID: UUID?

    private var layout: AnyLayout {
        axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
    }

    var body: some View {
        Group {
            if axis == .horizontal {
                ViewThatFits(in: .horizontal) {
                    dots
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            dots
                                .padding(.horizontal, 10)
                        }
                        .scrollIndicators(.never)
                        .scrollEdgeEffectStyle(.soft, for: .horizontal)
                        .background(SpaceSwipeExclusion())
                        .onAppear { reveal(in: proxy) }
                        .onChange(of: coordinator.browser.currentSpaceID) { _, _ in
                            withAnimation(.smooth(duration: 0.3)) { reveal(in: proxy) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                dots
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            coordinator.sidebarDrag.spaceSwitcherFrame = $0
        }
        .onChange(of: coordinator.sidebarDrag.springSpaceID) { _, armed in
            withAnimation(.smooth(duration: 0.25)) { hoveredID = armed }
        }
        .overlayPreferenceValue(SpaceDotAnchors.self) { anchors in
            Color.clear.preference(
                key: SpaceTipPlacement.self,
                value: axis == .horizontal
                    ? tipID.flatMap { id in anchors[id].flatMap { anchor in tip(for: id).map { (anchor, $0) } } }
                    : nil
            )
        }
        .onChange(of: hoveredID) { _, hovered in
            guard let hovered else {
                tipID = nil
                return
            }
            if tipID != nil {
                tipID = hovered
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard hoveredID == hovered else { return }
                withAnimation(.easeOut(duration: 0.12)) { tipID = hovered }
            }
        }
        .onChange(of: coordinator.spaceStore.spaces.map(\.id)) { _, ids in
            let live = Set(ids)
            coordinator.sidebarDrag.spaceDotFrames = coordinator.sidebarDrag.spaceDotFrames.filter { live.contains($0.key) }
        }
    }

    private func tip(for id: UUID) -> SpaceTip? {
        let spaces = coordinator.spaceStore.spaces
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return nil }
        return SpaceTip(name: spaces[index].name, shortcut: SpaceShortcut.label(at: index))
    }

    private func reveal(in proxy: ScrollViewProxy) {
        guard let id = coordinator.browser.currentSpaceID else { return }
        proxy.scrollTo(id, anchor: .center)
    }

    private var dots: some View {
        layout {
            ForEach(coordinator.spaceStore.spaces) { space in
                SpaceDot(
                    space: space,
                    slide: coordinator.overlays.spaceSlide,
                    currentID: coordinator.browser.currentSpaceID,
                    axis: axis,
                    hoveredID: $hoveredID
                ) {
                    coordinator.switchSpace(to: space)
                }
                .id(space.id)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    coordinator.sidebarDrag.spaceDotFrames[space.id] = $0
                }
                .contextMenu {
                    Button {
                        coordinator.spaceSlider.openEditor(.edit(space.id))
                    } label: {
                        Label("Edit Space…", systemImage: "pencil")
                    }
                    if coordinator.spaceStore.canRemove(space) {
                        Divider()
                        Button(role: .destructive) {
                            Task { await coordinator.confirmDeleteSpace(space) }
                        } label: {
                            Label("Delete Space…", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

private struct SpaceDot: View {
    let space: Space
    let slide: SpaceSlide
    let currentID: UUID?
    let axis: Axis
    @Binding var hoveredID: UUID?
    let action: () -> Void

    @State private var pointerInside = false
    @State private var taps = 0

    private var hovering: Bool {
        hoveredID == space.id
    }

    private var growth: CGFloat {
        if let hoveredID {
            return hoveredID == space.id ? 1 : 0
        }
        if let glide = slide.gliding {
            return space.id == glide.to ? 1 : 0
        }
        if space.id == currentID {
            return 1 - slide.travel
        }
        return space.id == slide.peer?.id ? slide.travel : 0
    }

    private var motion: SpaceDotMotion {
        if slide.gliding != nil {
            return .glide(turn: slide.glideTurn, velocity: slide.glideVelocity)
        }
        return slide.peer != nil && hoveredID == nil ? .track : .follow
    }

    var body: some View {
        let growth = growth
        Button {
            taps += 1
            action()
        } label: {
            SpaceDotGlyph(
                symbol: space.symbol,
                growth: growth,
                isHovered: hovering,
                isHoverActive: hoveredID != nil,
                motion: motion,
                taps: taps
            )
            .frame(width: SpaceDotGlyph.size.width, height: SpaceDotGlyph.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpaceDotButtonStyle())
        .onHover { over in
            pointerInside = over
            if over {
                withAnimation(.smooth(duration: 0.25)) { hoveredID = space.id }
            } else if hoveredID == space.id {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(90))
                    guard !pointerInside, hoveredID == space.id else { return }
                    withAnimation(.smooth(duration: 0.25)) { hoveredID = nil }
                }
            }
        }
        .help(axis == .vertical ? Text(verbatim: space.name) : Text(verbatim: ""))
        .anchorPreference(key: SpaceDotAnchors.self, value: .bounds) { [space.id: $0] }
        .accessibilityLabel(Text(verbatim: space.name))
        .accessibilityAddTraits(space.id == currentID ? .isSelected : [])
    }
}

private struct SpaceDotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct SidebarMoreMenu: View {
    let coordinator: AppCoordinator

    @State private var hovering = false
    @State private var isOpen = false

    private func run(_ action: @escaping () -> Void) -> () -> Void {
        {
            isOpen = false
            action()
        }
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            Image(systemName: "text.menu")
                .font(Theme.Font.rowTitle)
                .foregroundStyle(hovering || isOpen ? .primary : .secondary)
                .hoverLift(hovering)
                .frame(width: 28, height: 28)
                .hoverBackground(isActive: isOpen, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(String(localized: "More"))
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 1) {
                if coordinator.showsSpaces {
                    PopoverMenuRow(symbol: "plus", title: String(localized: "New Space…"), action: run {
                        coordinator.spaceSlider.openEditor(.new)
                    })
                    PopoverMenuDivider()
                }
                PopoverMenuRow(symbol: "eyeglasses", title: String(localized: "New Private Window"), action: run {
                    coordinator.enterPrivateBrowsing()
                })
                .disabled(coordinator.isSwitchingProfile)
                PopoverMenuDivider()
                PopoverMenuRow(symbol: "clock", title: String(localized: "History…"), action: run { coordinator.showHistory() })
                PopoverMenuRow(symbol: "gearshape", title: String(localized: "Settings…"), action: run { coordinator.openSettings() })
            }
            .padding(PopoverMenuRow<EmptyView>.inset)
            .frame(width: PopoverMenuRow<EmptyView>.width)
            .chromePopoverAppearance()
        }
    }
}

struct SpaceCreatePull: View {
    let slide: SpaceSlide

    var body: some View {
        let pull = slide.pull
        PullIndicator(
            state: PullState(progress: pull, armed: pull >= 1, tracking: pull > 0),
            symbol: "plus",
            turnsWithPull: false
        )
        .offset(x: 30 * (1 - pull))
        .padding(.trailing, 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SpaceDotAnchors: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

struct SpaceTip: View {
    let name: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: name)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let shortcut {
                Text(verbatim: shortcut)
                    .foregroundStyle(.secondary)
            }
        }
        .font(Theme.Font.row)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background {
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
    }
}

struct SpaceTipPlacement: PreferenceKey {
    static let defaultValue: (Anchor<CGRect>, SpaceTip)? = nil

    static func reduce(value: inout (Anchor<CGRect>, SpaceTip)?, nextValue: () -> (Anchor<CGRect>, SpaceTip)?) {
        value = value ?? nextValue()
    }
}
