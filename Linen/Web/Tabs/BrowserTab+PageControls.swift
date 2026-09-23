// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

extension BrowserTab {
    var isShowingRealPage: Bool {
        guard let scheme = webView.url?.scheme else { return false }
        return scheme != "about" && scheme != SystemPages.scheme
    }

    var backList: [WKBackForwardListItem] {
        guard isMaterialised else { return [] }
        return webView.backForwardList.backList
    }

    func goBack() {
        webView.stopLoading()
        webView.goBack()
    }

    func goForward() {
        webView.stopLoading()
        webView.goForward()
    }

    var zoomLevel: CGFloat {
        _ = zoomChanges
        return webView.pageZoom
    }

    var isZoomed: Bool {
        _ = zoomChanges
        return abs(webView.pageZoom - BrowserSettings.shared.pageZoom) > 0.005
            || abs(webView.magnification - 1) > 0.005
    }

    func zoomIn() {
        setPageZoom(webView.pageZoom + TabWebView.zoomStep)
    }

    func zoomOut() {
        setPageZoom(webView.pageZoom - TabWebView.zoomStep)
    }

    func resetZoom() {
        webView.magnification = 1
        webView.pageZoom = BrowserSettings.shared.pageZoom
        zoomDidChange()
    }

    private func setPageZoom(_ value: CGFloat) {
        webView.pageZoom = min(
            max(value, TabWebView.zoomRange.lowerBound),
            TabWebView.zoomRange.upperBound
        )
        zoomDidChange()
    }

    static func applyObscuredInsets(
        to webView: WKWebView,
        isUnderTopBar: Bool = false
    ) {
        let isFullscreen = switch webView.fullscreenState {
        case .enteringFullscreen, .inFullscreen:
            true
        default:
            false
        }
        webView.obscuredContentInsets = NSEdgeInsets(
            top: isFullscreen || !isUnderTopBar ? 0 : Theme.topBarHeight,
            left: 0,
            bottom: 0,
            right: 0
        )
    }

    static func restoreScrollScript(to y: Double) -> String {
        """
        (() => {
          const target = \(y);
          if (window.scrollY > 1) return;
          let expected = window.scrollY;
          let tries = 20;
          const step = () => {
            if (Math.abs(window.scrollY - expected) > 1) return;
            window.scrollTo(0, target);
            expected = window.scrollY;
            if (Math.abs(expected - target) <= 1 || --tries <= 0) return;
            setTimeout(step, 60);
          };
          step();
        })();
        """
    }

    static func wouldFlash(painting color: NSColor?, inDark: Bool) -> Bool {
        guard let painted = color?.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * painted.redComponent
            + 0.7152 * painted.greenComponent
            + 0.0722 * painted.blueComponent
        return inDark ? luminance > 0.5 : luminance < 0.5
    }
}
