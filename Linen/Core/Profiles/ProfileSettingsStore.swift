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
        guard !profile.isOriginal else { return AppDatabase.isRunningTests ? AppDatabase.testDefaults : .standard }
        return UserDefaults(suiteName: storageName(for: profile.id)) ?? .standard
    }

    static func forget(_ id: UUID) {
        UserDefaults.standard.removePersistentDomain(forName: storageName(for: id))
    }

    private static func storageName(for id: UUID) -> String {
        AppDatabase.isRunningTests ? AppDatabase.testDefaultsName(suiteName(for: id)) : suiteName(for: id)
    }
}
