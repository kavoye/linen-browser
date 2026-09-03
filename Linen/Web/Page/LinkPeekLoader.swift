// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import WebKit

struct LinkPeekPage {
    let title: String
    let description: String
    let text: String
    let snapshot: NSImage?
    let didFinishLoading: Bool
    let mediaCount: Int

    var hasReadableContent: Bool {
        text.count >= LinkPeekLoader.minimumText || description.count >= 40
    }
}

@MainActor
final class LinkPeekLoader {
    static let minimumText = 240
    static let textBudget = 5000

    private static let loadCeiling: Duration = .seconds(8)
    private static let quietCeiling: Duration = .milliseconds(700)
    private static let snapshotWidth: CGFloat = 640

    private var webView: WKWebView?

    static func canPeek(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return url.host() != nil && !SystemPages.isSystem(url)
    }

    func load(_ url: URL) async throws -> LinkPeekPage {
        let view = surface()
        view.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8))

        let finished = await PageSettle.untilIdle(view, timeout: Self.loadCeiling)
        try Task.checkCancellation()
        await PageSettle.untilQuiet(view, ceiling: Self.quietCeiling)
        try Task.checkCancellation()

        let object = await evaluate(Self.script, in: view)
        try Task.checkCancellation()

        let snapshot = await ResearchPreview.capture(view, width: Self.snapshotWidth)
        try Task.checkCancellation()

        return LinkPeekPage(
            title: object?["title"] as? String ?? "",
            description: object?["description"] as? String ?? "",
            text: String((object?["text"] as? String ?? "").prefix(Self.textBudget)),
            snapshot: snapshot,
            didFinishLoading: finished,
            mediaCount: object?["media"] as? Int ?? 0
        )
    }

    func stop() {
        webView?.stopLoading()
        guard let blank = URL(string: "about:blank") else { return }
        webView?.load(URLRequest(url: blank))
    }

    func release() {
        stop()
        webView = nil
    }

    private func surface() -> WKWebView {
        if let webView {
            return webView
        }
        let configuration = AgentToolkit.researchConfiguration(extensionController: nil)
        let view = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1000, height: 720),
            configuration: configuration
        )
        BrowserSettings.shared.apply(to: view)
        view.customUserAgent = WebViewPool.safariUserAgent
        webView = view
        return view
    }

    private func evaluate(_ script: String, in webView: WKWebView) async -> [String: Any]? {
        let value = try? await webView.evaluateJavaScript(script)
        guard let text = value as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static let script = #"""
    (() => {
      const clean = s => (s || '').replace(/\s+/g, ' ').trim();
      const meta = names => {
        for (const name of names) {
          const el = document.querySelector('meta[property="' + name + '"]')
            || document.querySelector('meta[name="' + name + '"]');
          if (el && el.content) return clean(el.content);
        }
        return '';
      };
      const media = () => {
        let count = 0;
        for (const el of document.querySelectorAll('img, video')) {
          const box = el.getBoundingClientRect();
          if (box.width >= 200 && box.height >= 150) count += 1;
        }
        return count;
      };
      const root = document.querySelector('article')
        || document.querySelector('main')
        || document.querySelector('[role="main"]')
        || document.body;
      let text = root ? clean(root.innerText) : '';
      if (text.length < 240 && document.body) text = clean(document.body.innerText);
      return JSON.stringify({
        title: clean(document.title),
        description: meta(['og:description', 'twitter:description', 'description']),
        text: text.slice(0, 6000),
        media: media()
      });
    })()
    """#
}
