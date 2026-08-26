// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SidebarProfileControl: View {
    let coordinator: AppCoordinator

    private var profiles: ProfileStore {
        coordinator.profiles
    }

    private var profile: Profile {
        profiles.current
    }

    private var isPlain: Bool {
        !profiles.isPrivate && profile.id == profiles.profiles.first?.id
    }

    private var tint: Color? {
        isPlain ? nil : profile.color.tint
    }

    private var name: String {
        profiles.isPrivate ? profiles.privateBrowsing.name : profile.name
    }

    var body: some View {
        QuietIconButton(
            symbol: profiles.isPrivate ? profiles.privateBrowsing.symbol : profile.symbol,
            isOn: coordinator.isProfileSwitcherOpen,
            tint: tint,
            help: String(localized: "Profile — \(name)")
        ) {
            coordinator.isProfileSwitcherOpen.toggle()
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            coordinator.profileButtonFrame = $0
        }
    }
}
