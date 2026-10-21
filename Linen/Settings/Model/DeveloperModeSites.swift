// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct DeveloperModeSites: Equatable {
    var enabled: Set<String> = []
    var disabled: Set<String> = []

    func uses(_ url: URL?) -> Bool {
        guard let host = DeveloperMode.host(of: url) else { return false }
        if enabled.contains(host) {
            return true
        }
        if disabled.contains(host) {
            return false
        }
        return DeveloperMode.isLocal(host)
    }

    mutating func set(_ isOn: Bool, for url: URL?) {
        guard let host = DeveloperMode.host(of: url) else { return }
        enabled.remove(host)
        disabled.remove(host)
        guard isOn != DeveloperMode.isLocal(host) else { return }
        if isOn {
            enabled.insert(host)
        } else {
            disabled.insert(host)
        }
    }
}
