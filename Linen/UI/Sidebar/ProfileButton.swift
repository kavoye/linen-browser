// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ProfileGlyph: View {
    let profile: Profile
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(profile.color.tint.opacity(0.16))
            .overlay(
                Circle()
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

struct ProfileSwitcher: View {
    let coordinator: AppCoordinator
    let dismiss: () -> Void

    static let inset: CGFloat = 6
    static var rowRadius: CGFloat {
        Theme.Radius.nested(in: Theme.Radius.panel, inset: inset)
    }

    private var profiles: ProfileStore {
        coordinator.profiles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !profiles.isPrivate {
                ForEach(profiles.profiles) { profile in
                    ProfileSwitcherRow(
                        profile: profile,
                        isCurrent: profile.id == profiles.current.id
                    ) {
                        dismiss()
                        Task { await coordinator.switchProfile(to: profile) }
                    }
                    .disabled(coordinator.isSwitchingProfile)
                }

                Divider()
                    .opacity(0.4)
                    .padding(.vertical, 5)
            }

            ProfileActionRow(title: "New Private Window", symbol: "eyeglasses") {
                dismiss()
                coordinator.enterPrivateBrowsing()
            }
            .disabled(coordinator.isSwitchingProfile)

            ProfileActionRow(title: "Manage Profiles…", symbol: "person.2") {
                dismiss()
                coordinator.openSettings(.profiles)
            }
        }
        .padding(Self.inset)
        .frame(width: 208)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 8)
    }
}

private struct ProfileSwitcherRow: View {
    let profile: Profile
    let isCurrent: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @Environment(\.chromeWash) private var wash

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ProfileGlyph(profile: profile, size: 26)

                Text(verbatim: profile.name)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(Theme.Font.badge)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: ProfileSwitcher.rowRadius, style: .continuous)
                    .fill(hovering ? wash.layer(0.12) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
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
    @Environment(\.chromeWash) private var wash

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
            .background {
                RoundedRectangle(cornerRadius: ProfileSwitcher.rowRadius, style: .continuous)
                    .fill(hovering ? wash.layer(0.12) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = isEnabled && $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
