// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

@MainActor
final class WebViewObservations {
    private var tokens: [NSKeyValueObservation] = []

    func watch<Value>(
        _ view: WKWebView,
        _ keyPath: KeyPath<WKWebView, Value>,
        initially: Bool = false,
        _ handler: @escaping @MainActor (WKWebView) -> Void
    ) {
        let options: NSKeyValueObservingOptions = initially ? [.new, .initial] : [.new]
        tokens.append(view.observe(keyPath, options: options) { view, _ in
            MainActor.assumeIsolated { handler(view) }
        })
    }

    func cancel() {
        tokens.removeAll()
    }
}
