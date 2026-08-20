// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import WebKit

@MainActor
enum WebProcessFootprint {
    private static let pidGetter = Selector(("_webProcessIdentifier"))

    static let isSupported = WKWebView.instancesRespond(to: pidGetter)

    static func bytes(of webView: WKWebView) -> UInt64? {
        guard isSupported,
              let pid = (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value,
              pid > 0
        else { return nil }
        return footprint(of: pid)
    }

    private static func footprint(of pid: pid_t) -> UInt64? {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0, usage.ri_phys_footprint > 0 else { return nil }
        return usage.ri_phys_footprint
    }
}
