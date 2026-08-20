// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum PageColorSampling {
    private static let colorGetter = Selector(("_sampledPageTopColor"))
    private static let maxDifferenceSetter = Selector(("_setSampledPageTopColorMaxDifference:"))

    static let isSupported = WKWebView.instancesRespond(to: colorGetter)
        && WKWebViewConfiguration.instancesRespond(to: maxDifferenceSetter)

    nonisolated static let colorKey = "_sampledPageTopColor"

    static func enable(on configuration: WKWebViewConfiguration) {
        guard isSupported else { return }
        // The key drops the leading underscore. KVC finds WebKit's
        // `_setSampledPageTopColorMaxDifference:` from this spelling; the
        // underscored key throws.
        configuration.setValue(5.0, forKey: "sampledPageTopColorMaxDifference")
    }

    static func sampledTopColor(of webView: WKWebView) -> NSColor? {
        guard isSupported else { return nil }
        return webView.value(forKey: colorKey) as? NSColor
    }
}
