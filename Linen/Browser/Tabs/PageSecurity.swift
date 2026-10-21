// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

enum PageSecurity: Equatable {
    case secure
    case pending
    case mixed
    case insecure
    case none

    @MainActor
    init(of view: WKWebView, showingError: Bool) {
        guard !showingError, let scheme = view.url?.scheme else {
            self = .none
            return
        }
        switch scheme {
        case "https":
            if view.isLoading {
                self = .pending
            } else {
                self = view.hasOnlySecureContent ? .secure : .mixed
            }
        case "http":
            self = .insecure
        default:
            self = .none
        }
    }
}
