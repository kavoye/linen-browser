// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension URL {
    var displayHost: String? {
        guard let host = host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayAddress: String? {
        guard let host = displayHost else { return nil }
        let path = path().removingPercentEncoding ?? path()
        guard path != "/", !path.isEmpty else { return host }
        return host + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }
}
