// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ProfileSettingsStore {
    static func suiteName(for id: UUID) -> String {
        "app.linen.profile.\(id.uuidString)"
    }

    @MainActor
    static func defaults(for profile: Profile) -> UserDefaults {
        #if DEBUG
        if StageMode.isActive {
            return StageMode.defaults
        }
        #endif
        guard !profile.isOriginal else { return .standard }
        return UserDefaults(suiteName: suiteName(for: profile.id)) ?? .standard
    }

    static func forget(_ id: UUID) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName(for: id))
    }
}
