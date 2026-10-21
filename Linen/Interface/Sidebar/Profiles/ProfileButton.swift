// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ProfileSwitcherLayer: View {
    let coordinator: AppCoordinator

    var body: some View {
        @Bindable var overlays = coordinator.overlays
        if overlays.isProfileSwitcherOpen, let anchor = overlays.profileButtonFrame {
            GeometryReader { proxy in
                let local = anchor.offsetBy(dx: -proxy.frame(in: .global).minX, dy: -proxy.frame(in: .global).minY)
                let iconLead = PopoverMenuRow<EmptyView>.inset + 8 + 10
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { overlays.isProfileSwitcherOpen = false }

                    ProfileSwitcher(coordinator: coordinator, isPresented: $overlays.isProfileSwitcherOpen)
                        .padding(.leading, max(LoomChrome.canvasInset, local.midX - iconLead))
                        .padding(.bottom, max(0, proxy.size.height - local.minY + 8))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .transition(.opacity)
        }
    }
}

struct ProfileSwitcher: View {
    let coordinator: AppCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ProfileMenuRows(coordinator: coordinator, isPresented: $isPresented)
        }
        .padding(PopoverMenuRow<EmptyView>.inset)
        .frame(width: PopoverMenuRow<EmptyView>.width)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.systemPopover, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 8)
    }
}

struct ProfileMenuRows: View {
    let coordinator: AppCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        if coordinator.showsSpaces {
            ForEach(coordinator.spaceStore.spaces) { space in
                PopoverMenuRow(title: space.name, isChecked: space.id == coordinator.browser.currentSpaceID) {
                    Circle()
                        .fill(Color(nsColor: space.color == .gray ? .systemGray : space.color.nsTint))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: space.symbol)
                                .symbolVariant(.fill)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                } action: {
                    isPresented = false
                    coordinator.switchSpace(to: space)
                }
                .disabled(coordinator.isSwitchingProfile)
            }

            PopoverMenuDivider()
        }

        PopoverMenuRow(symbol: "plus.square.fill", title: String(localized: "New Private Window")) {
            isPresented = false
            coordinator.enterPrivateBrowsing()
        }
        .disabled(coordinator.isSwitchingProfile)
    }
}

struct PopoverMenuRow<Icon: View>: View {
    let title: String
    var isChecked = false
    var shortcut: String?
    @ViewBuilder let icon: Icon
    let action: () -> Void

    static var inset: CGFloat {
        6
    }
    static var width: CGFloat {
        236
    }

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon
                    .frame(width: 20, height: 20)
                Text(verbatim: title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let shortcut {
                    KeyCaps(shortcut)
                }
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .hoverBackground(
                isActive: hovering && isEnabled,
                in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }

    private static var rowRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.systemPopover, inset: inset)
    }
}

extension PopoverMenuRow where Icon == PopoverMenuSymbol {
    init(symbol: String, title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, shortcut: shortcut, icon: { PopoverMenuSymbol(name: symbol) }, action: action)
    }
}

struct PopoverMenuSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }
}

struct PopoverMenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}
