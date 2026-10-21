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
        if SystemPages.isStart(pinnedURL) {
            return urlString.isEmpty && SystemPages.showsStartFace(self)
        }
        return urlString == pinnedURL.absoluteString
    }

    var pinnableURL: URL? {
        guard !urlString.isEmpty else {
            return SystemPages.showsStartFace(self) ? SystemPages.start : nil
        }
        return URL(string: urlString)
    }
}
