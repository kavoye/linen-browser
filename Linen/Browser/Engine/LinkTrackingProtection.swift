// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

enum LinkTrackingProtection {
    static func enable(on preferences: WKPreferences) {
        WebKitFeatures.turnOnUnlessOverridden("FilterLinkDecorationByDefaultEnabled", in: preferences)
    }
}
