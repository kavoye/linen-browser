// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

final class FaviconWatcher: NSObject, WKScriptMessageHandler {
    static let shared = FaviconWatcher()

    private static let handlerName = "linenFavicon"
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()

    func install(in webView: TabWebView) {
        guard !webView.hasFaviconWatcher else { return }
        webView.hasFaviconWatcher = true

        let controller = webView.configuration.userContentController
        guard !installedControllers.contains(controller) else { return }
        installedControllers.add(controller)
        controller.addUserScript(WKUserScript(
            source: Self.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let webView = message.webView as? TabWebView else { return }
        webView.onFaviconDeclarationChange?()
    }

    private static let script = #"""
    (() => {
      if (window.__linenFavicon) return;
      window.__linenFavicon = true;

      const channel = window.webkit?.messageHandlers?.linenFavicon;
      if (!channel) return;

      const isIcon = node =>
        node?.tagName === 'LINK' && /(^|\s)(icon|apple-touch-icon)(\s|$)/i.test(node.rel || '');

      let pending = 0;
      const report = () => {
        clearTimeout(pending);
        pending = setTimeout(() => channel.postMessage(1), 60);
      };

      const observer = new MutationObserver(records => {
        for (const record of records) {
          if (record.type === 'attributes' && isIcon(record.target)) { report(); return; }
          for (const node of record.addedNodes) {
            if (isIcon(node)) { report(); return; }
          }
        }
      });

      const start = () => observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['href', 'rel', 'media', 'sizes'],
      });

      if (document.documentElement) {
        start();
      } else {
        document.addEventListener('readystatechange', start, { once: true });
      }
    })()
    """#
}
