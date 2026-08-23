// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SidebarProfileButton: View {
    let coordinator: AppCoordinator

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false
    @State private var switching = false

    private var profiles: ProfileStore {
        coordinator.profiles
    }
    private var current: Profile {
        profiles.current
    }

    private var showsName: Bool {
        sidebarStyle == .full
    }

    private var symbolTint: AnyShapeStyle {
        AnyShapeStyle(current.color.tint)
    }

    var body: some View {
        Button {
            switching = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: current.symbol)
                    .font(Theme.Font.title)
                    .foregroundStyle(symbolTint)
                    .frame(width: 16)

                if showsName {
                    Text(verbatim: current.name)
                        .font(Theme.Font.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, showsName ? 9 : 0)
            .frame(minWidth: SidebarMetrics.controlHeight, maxWidth: .infinity)
            .frame(height: SidebarMetrics.controlHeight)
            .sidebarRowSelectionEffect(isSelected: switching, isHovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("Profile — \(current.name)"))
        .popover(isPresented: $switching, arrowEdge: .top) {
            ProfileSwitcher(coordinator: coordinator, isPresented: $switching)
        }
    }
}

struct ProfileGlyph: View {
    let profile: Profile
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(profile.color.tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(profile.color.tint.opacity(0.22), lineWidth: 1)
            )
            .overlay {
                Image(systemName: profile.symbol)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundStyle(profile.color.tint)
            }
            .frame(width: size, height: size)
    }
}

private struct ProfileSwitcher: View {
    let coordinator: AppCoordinator
    @Binding var isPresented: Bool

    static let inset: CGFloat = 6
    static var rowRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.panel, inset: inset)
    }

    private var profiles: ProfileStore {
        coordinator.profiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(profiles.profiles) { profile in
                ProfileSwitcherRow(
                    profile: profile,
                    isCurrent: profile.id == profiles.current.id,
                    caption: caption(for: profile)
                ) {
                    isPresented = false
                    Task { await coordinator.switchProfile(to: profile) }
                }
                .disabled(coordinator.isSwitchingProfile)
            }

            Divider()
                .opacity(0.4)
                .padding(.vertical, 5)

            ProfileSwitcherRow(
                profile: profiles.privateBrowsing,
                isCurrent: profiles.isPrivate,
                caption: privateCaption
            ) {
                isPresented = false
                coordinator.enterPrivateBrowsing()
            }
            .disabled(coordinator.isSwitchingProfile)

            if profiles.isPrivate || coordinator.hasPrivateSession {
                ProfileActionRow(title: "Leave Private Browsing", symbol: "xmark.circle") {
                    isPresented = false
                    coordinator.leavePrivateBrowsing()
                }
                .disabled(coordinator.isSwitchingProfile)
            }

            ProfileActionRow(title: "Manage Profiles…", symbol: "person.2") {
                isPresented = false
                coordinator.openSettings(.profiles)
            }
        }
        .padding(Self.inset)
        .frame(width: 244)
    }

    private func caption(for profile: Profile) -> LocalizedStringResource? {
        guard profile.id == profiles.current.id else { return nil }
        return "Browsing now"
    }

    private var privateCaption: LocalizedStringResource? {
        if profiles.isPrivate {
            return "Browsing now"
        }
        return coordinator.hasPrivateSession ? "Session waiting" : nil
    }
}

private struct ProfileSwitcherRow: View {
    let profile: Profile
    let isCurrent: Bool
    var caption: LocalizedStringResource?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ProfileGlyph(profile: profile, size: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: profile.name)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let caption {
                        Text(caption)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(Theme.Font.badge)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .sidebarRowSelectionEffect(
                isSelected: false,
                isHovering: hovering,
                radius: ProfileSwitcher.rowRadius
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct ProfileActionRow: View {
    let title: LocalizedStringResource
    let symbol: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)

                Text(title)
                    .font(Theme.Font.row)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .sidebarRowSelectionEffect(
                isSelected: false,
                isHovering: hovering,
                radius: ProfileSwitcher.rowRadius
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
