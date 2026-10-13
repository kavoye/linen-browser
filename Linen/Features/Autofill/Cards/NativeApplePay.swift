// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

enum NativeApplePay {
    static func apply(to preferences: WKPreferences) {
        guard preferences.responds(to: NSSelectorFromString("_setApplePayEnabled:")) else { return }
        preferences.setValue(false, forKey: "applePayEnabled")
    }
}
