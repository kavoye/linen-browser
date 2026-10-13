// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

final class SettingsDefaults {
    let app: UserDefaults
    private(set) var session: UserDefaults
    private let sessionKeys: Set<String>

    init(app: UserDefaults, session: UserDefaults, sessionKeys: Set<String>) {
        self.app = app
        self.session = session
        self.sessionKeys = sessionKeys
    }

    func isSessionKey(_ key: String) -> Bool {
        sessionKeys.contains(key)
    }

    func useSession(_ defaults: UserDefaults) -> Bool {
        guard defaults !== session else { return false }
        session = defaults
        return true
    }

    func set(_ value: Any?, forKey key: String) {
        store(for: key).set(value, forKey: key)
    }

    func string(_ key: String) -> String? {
        store(for: key).string(forKey: key)
    }

    func bool(_ key: String) -> Bool {
        store(for: key).bool(forKey: key)
    }

    func object(_ key: String) -> Any? {
        store(for: key).object(forKey: key)
    }

    func double(_ key: String) -> Double {
        store(for: key).double(forKey: key)
    }

    func stringArray(_ key: String) -> [String]? {
        store(for: key).stringArray(forKey: key)
    }

    private func store(for key: String) -> UserDefaults {
        isSessionKey(key) ? session : app
    }
}
