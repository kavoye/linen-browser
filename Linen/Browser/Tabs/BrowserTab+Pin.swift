// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BrowserTab {
    var isAwayFromPin: Bool {
        guard let pinnedURL else { return false }
        return !urlString.isEmpty && urlString != pinnedURL.absoluteString
    }

    var isShowingPin: Bool {
        guard let pinnedURL else { return false }
        return urlString == pinnedURL.absoluteString
    }
}
