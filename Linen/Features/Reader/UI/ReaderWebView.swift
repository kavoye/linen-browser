// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct ReaderWebView: NSViewRepresentable {
    let session: ReaderSession
    let article: ReaderArticle
    let dataStore: WKWebsiteDataStore
    let typeface: ReaderAppearance.Typeface
    let palette: ReaderAppearance.Palette
    let textSize: Int
    let block: Int?
    let onLoaded: () -> Void
    let onOpenLink: (URL, _ inNewTab: Bool, _ activate: Bool) -> Void

    func makeCoordinator() -> ReaderPageController {
        ReaderPageController()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        session.presentedView = webView
        update(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: ReaderPageController) {
        if coordinator.session?.presentedView === webView {
            coordinator.session?.presentedView = nil
        }
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    private func update(_ controller: ReaderPageController) {
        controller.session = session
        controller.onLoaded = onLoaded
        controller.onOpenLink = onOpenLink
        controller.show(
            article,
            appearance: .init(typeface: typeface, palette: palette, textSize: textSize),
            block: block
        )
    }
}

@MainActor
final class ReaderPageController: NSObject, WKNavigationDelegate {
    struct Appearance: Equatable {
        let typeface: ReaderAppearance.Typeface
        let palette: ReaderAppearance.Palette
        let textSize: Int
    }

    weak var webView: WKWebView?
    weak var session: ReaderSession?
    var onLoaded: (() -> Void)?
    var onOpenLink: ((URL, Bool, Bool) -> Void)?

    private var article: ReaderArticle?
    private var appearance: Appearance?
    private var block: Int?
    private var isLoaded = false
    private var acceptsNextLoad = false

    private static let middleButton = 4

    func show(_ next: ReaderArticle, appearance nextAppearance: Appearance, block nextBlock: Int?) {
        guard let webView else { return }
        if article != next {
            article = next
            appearance = nextAppearance
            block = nextBlock
            isLoaded = false
            acceptsNextLoad = true
            let html = ReaderPage.html(
                for: next,
                typeface: nextAppearance.typeface,
                palette: nextAppearance.palette,
                textSize: nextAppearance.textSize
            )
            webView.loadHTMLString(html, baseURL: next.url)
            return
        }
        if appearance != nextAppearance {
            appearance = nextAppearance
            if isLoaded {
                run(ReaderPage.appearanceScript(
                    typeface: nextAppearance.typeface,
                    palette: nextAppearance.palette,
                    textSize: nextAppearance.textSize
                ))
            }
        }
        if block != nextBlock {
            block = nextBlock
            if isLoaded {
                run(ReaderPage.highlightScript(block: nextBlock))
            }
        }
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.cancel)
            return
        }
        if acceptsNextLoad, navigationAction.navigationType == .other {
            acceptsNextLoad = false
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
        else { return }
        if let article, let fragment = url.fragment(), !fragment.isEmpty,
           BrowserTab.withoutFragment(url.absoluteString) == BrowserTab.withoutFragment(article.url.absoluteString) {
            scroll(toFragment: fragment)
            return
        }
        let inNewTab = navigationAction.modifierFlags.contains(.command)
            || navigationAction.buttonNumber == Self.middleButton
        onOpenLink?(url, inNewTab, navigationAction.modifierFlags.contains(.shift))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        onLoaded?()
        if let appearance {
            run(ReaderPage.appearanceScript(
                typeface: appearance.typeface,
                palette: appearance.palette,
                textSize: appearance.textSize
            ))
        }
        if block != nil {
            run(ReaderPage.highlightScript(block: block))
        }
    }

    private func scroll(toFragment fragment: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [fragment], options: []),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        run("""
        (() => {
          const id = \(encoded)[0];
          const el = document.getElementById(id) || document.getElementsByName(id)[0];
          if (el) el.scrollIntoView({ block: 'start', behavior: 'smooth' });
        })()
        """)
    }
}
