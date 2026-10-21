// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

extension BrowserSettings {
    func apply(to configuration: WKWebViewConfiguration) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = javaScriptEnabled
        configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        FingerprintingProtection.enable(on: configuration.defaultWebpagePreferences)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !blocksPopups
        configuration.mediaTypesRequiringUserActionForPlayback = javaScriptEnabled ? [] : autoplay.mediaTypes
        configuration.preferences.isElementFullscreenEnabled = true
        // `isInspectable` only lets an external inspector attach. This private
        // preference enables the page's own Inspect Element item.
        configuration.preferences.setValue(webInspectorEnabled, forKey: "developerExtrasEnabled")
        WebKitFeatures.apply(to: configuration.preferences)
        NativeApplePay.apply(to: configuration.preferences)
        UserInstalledFonts.hide(from: configuration.preferences)
    }

    func apply(to webView: WKWebView) {
        apply(to: webView.configuration)
        if webView.pageZoom != pageZoom {
            webView.pageZoom = pageZoom
        }
        webView.customUserAgent = userAgentString
        applyInspector(to: webView)
    }

    func applyInspector(to webView: WKWebView) {
        let isEnabled = webInspectorEnabled || usesDeveloperMode(for: webView.url)
        webView.configuration.preferences.setValue(isEnabled, forKey: "developerExtrasEnabled")
        webView.isInspectable = isEnabled
    }
}
