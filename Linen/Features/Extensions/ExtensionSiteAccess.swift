// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum ExtensionSiteAccess {
    nonisolated static func website(of url: URL?) -> String? {
        guard let url, url.scheme == "https" || url.scheme == "http",
              var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }

    static func websitePattern(for host: String) -> WKWebExtension.MatchPattern? {
        let literal = host.contains(":") ? "[\(host)]" : host
        return try? WKWebExtension.MatchPattern(string: "*://*.\(literal)/*")
    }

    nonisolated static func website(_ host: String, isCoveredBy blocked: String) -> Bool {
        host == blocked || host.hasSuffix("." + blocked)
    }
}
