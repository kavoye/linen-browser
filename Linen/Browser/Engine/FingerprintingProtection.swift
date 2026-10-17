// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

@objc protocol PrivacyPolicySetting {
    @objc(_setNetworkConnectionIntegrityPolicy:)
    func setPolicy(_ policy: UInt)
}

enum FingerprintingProtection {
    private static let noise: UInt = 1 << 6
    private static let setter = #selector(PrivacyPolicySetting.setPolicy(_:))

    static func enable(on preferences: WKWebpagePreferences) {
        guard preferences.responds(to: setter) else { return }
        let current = preferences.value(forKey: "_networkConnectionIntegrityPolicy") as? UInt ?? 0
        unsafeBitCast(preferences, to: PrivacyPolicySetting.self).setPolicy(current | noise)
    }
}
