// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import os
import WebKit

extension MediaCenter {
    nonisolated private static let canToggleSelector = Selector(("_canTogglePictureInPicture"))
    nonisolated private static let toggleSelector = Selector(("_togglePictureInPicture"))
    nonisolated private static let isActiveSelector = Selector(("_isPictureInPictureActive"))

    nonisolated static func canTogglePictureInPicture(_ webView: WKWebView) -> Bool {
        answersTrue(canToggleSelector, on: webView)
    }

    nonisolated static func pictureInPictureActive(_ webView: WKWebView) -> Bool? {
        guard webView.responds(to: isActiveSelector) else { return nil }
        return answersTrue(isActiveSelector, on: webView)
    }

    @discardableResult
    nonisolated static func togglePictureInPicture(on webView: WKWebView) -> Bool {
        guard webView.responds(to: toggleSelector) else {
            Pipeline.log.notice("media: no toggle SPI, falling back to a synthesized gesture")
            return false
        }
        webView.perform(toggleSelector)
        return true
    }

    nonisolated private static func answersTrue(_ selector: Selector, on webView: WKWebView) -> Bool {
        guard webView.responds(to: selector), let method = webView.method(for: selector) else {
            return false
        }
        typealias Answer = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method, to: Answer.self)(webView, selector)
    }

    static func enablePictureInPicture(on preferences: WKPreferences) {
        if preferences.responds(to: Selector(("_setAllowsPictureInPictureMediaPlayback:"))) {
            preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        enablePiPFeatureFlags(on: preferences)
    }

    private static func enablePiPFeatureFlags(on preferences: WKPreferences) {
        let featuresSelector = Selector(("_features"))
        guard (WKPreferences.self as AnyObject).responds(to: featuresSelector),
              preferences.responds(to: #selector(WebKitFeatureToggling.setEnabled(_:for:))),
              let result = (WKPreferences.self as AnyObject).perform(featuresSelector),
              let features = result.takeUnretainedValue() as? [AnyObject]
        else {
            Pipeline.log.notice("media: feature-flag SPI unavailable, native PiP off")
            return
        }

        let switcher = unsafeBitCast(preferences, to: WebKitFeatureToggling.self)

        for feature in features {
            let key = (feature.value(forKey: "key") as? String) ?? ""
            let lowered = key.lowercased()
            guard lowered.contains("pictureinpicture") || lowered.contains("presentationmode") else {
                continue
            }
            switcher.setEnabled(true, for: feature)
        }
    }
}
