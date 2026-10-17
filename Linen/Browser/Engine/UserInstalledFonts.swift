// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

enum UserInstalledFonts {
    static func hide(from preferences: WKPreferences) {
        guard preferences.responds(to: NSSelectorFromString("_setShouldAllowUserInstalledFonts:")) else { return }
        preferences.setValue(false, forKey: "shouldAllowUserInstalledFonts")
    }
}
