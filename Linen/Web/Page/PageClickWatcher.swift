// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

final class PageClickWatcher: NSObject, WKScriptMessageHandler {
    static let shared = PageClickWatcher()

    @MainActor var onClick: ((CGPoint) -> Void)?

    private static let handlerName = "linenClick"
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()

    @MainActor
    func install(in webView: TabWebView) {
        guard !webView.hasClickWatcher else { return }
        webView.hasClickWatcher = true

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
        guard let webView = message.webView,
              let point = message.body as? [Double],
              point.count == 2,
              let content = webView.window?.contentView
        else { return }

        let zoom = webView.pageZoom
        let y = point[1] * zoom
        let inView = CGPoint(
            x: point[0] * zoom,
            y: webView.isFlipped ? y : webView.bounds.height - y
        )
        let inWindow = webView.convert(inView, to: nil)
        let inContent = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        MainActor.assumeIsolated {
            onClick?(inContent)
        }
    }

    private static let script = """
    (function () {
      if (window !== window.top) { return; }
      document.addEventListener('mousedown', function (event) {
        try {
          window.webkit.messageHandlers.linenClick.postMessage([event.clientX, event.clientY]);
        } catch (error) {}
      }, true);
    })();
    """
}
