// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
final class PageFrameRegistry: NSObject, WKScriptMessageHandler {
    static let shared = PageFrameRegistry()
    static let handlerName = "linenFrameRegistry"
    static let script = """
        (() => {
          if (window.__linenFrameToken) return;
          const token = Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16)).join('-');
          Object.defineProperty(window, '__linenFrameToken', { value: token });
          window.webkit.messageHandlers.linenFrameRegistry.postMessage(token);
        })();
        """

    final class Target {
        let id: String
        let root: String
        let frame: WKFrameInfo
        let url: URL
        init(id: String, root: String, frame: WKFrameInfo, url: URL) {
            self.id = id
            self.root = root
            self.frame = frame
            self.url = url
        }
    }

    private final class Store {
        var root = ""
        var frames: [String: Target] = [:]
    }
    private let stores = NSMapTable<WKWebView, Store>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    static func install(in controller: WKUserContentController) {
        controller.add(shared, contentWorld: PageAutomationGuard.world, name: handlerName)
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: PageAutomationGuard.world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView, let token = message.body as? String, token.count <= 80 else { return }
        let store = stores.object(forKey: view) ?? Store()
        stores.setObject(store, forKey: view)
        if message.frameInfo.isMainFrame {
            store.root = token
            store.frames = [:]
            return
        }
        guard !store.root.isEmpty, let url = message.frameInfo.request.url,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host()?.lowercased() == message.frameInfo.securityOrigin.host.lowercased(),
              url.scheme?.lowercased() == message.frameInfo.securityOrigin.protocol.lowercased(),
              Self.portMatches(url: url, securityPort: message.frameInfo.securityOrigin.port),
              store.frames.count < 256 else { return }
        store.frames[token] = Target(id: token, root: store.root, frame: message.frameInfo, url: url)
    }

    func targets(in view: WKWebView) -> [Target] {
        Array(stores.object(forKey: view)?.frames.values ?? [String: Target]().values).sorted { $0.id < $1.id }
    }

    nonisolated static func portMatches(url: URL, securityPort: Int) -> Bool {
        let standard = url.scheme?.lowercased() == "https" ? 443 : 80
        return (url.port ?? standard) == (securityPort == 0 ? standard : securityPort)
    }

    func target(_ id: String, in view: WKWebView) -> Target? {
        stores.object(forKey: view)?.frames[id]
    }

    func isCurrent(_ target: Target, in view: WKWebView) -> Bool {
        let store = stores.object(forKey: view)
        return store?.root == target.root && store?.frames[target.id] === target
    }

    func isLive(_ target: Target, in view: WKWebView) async -> Bool {
        guard isCurrent(target, in: view), let token = try? await view.evaluateJavaScript(
            "window.__linenFrameToken", in: target.frame, contentWorld: PageAutomationGuard.world) as? String else { return false }
        return token == target.id && isCurrent(target, in: view)
    }
}

extension PageDriver {
    @TaskLocal static var selectedFrame: PageFrameRegistry.Target?
}
