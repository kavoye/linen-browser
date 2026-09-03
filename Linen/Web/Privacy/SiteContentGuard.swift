// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

/// WebKit fixes `mediaTypesRequiringUserActionForPlayback` when a web view is
/// made, so a per-website auto-play answer can only be kept in the page.
final class SiteContentGuard: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = SiteContentGuard()

    private static let handlerName = "linenSiteGuard"
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()

    func install(in webView: TabWebView) {
        guard !webView.hasSiteGuard else { return }
        webView.hasSiteGuard = true

        let controller = webView.configuration.userContentController
        guard !installedControllers.contains(controller) else { return }
        installedControllers.add(controller)
        controller.addUserScript(WKUserScript(
            source: Self.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.handlerName)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let webView = message.webView as? TabWebView,
              let body = message.body as? [String: Any]
        else { return (nil, nil) }

        if let blocked = body["blocked"] as? String {
            webView.onPopupBlocked?(URL(string: blocked))
            return (nil, nil)
        }

        let origin = SitePermissions.origin(for: webView.url)
        let settings = BrowserSettings.shared
        let permissions = SitePermissions.shared
        let autoplay = permissions.autoplay(for: origin) ?? settings.autoplay
        let popups = permissions.popups(for: origin)
            ?? (settings.blocksPopups ? PopupPolicy.blockAndNotify : .allow)
        return (["autoplay": autoplay.rawValue, "popups": popups.rawValue], nil)
    }

    private static let script = #"""
    (() => {
      if (window.__linenSiteGuard) return;

      const channel = window.webkit?.messageHandlers?.linenSiteGuard;
      if (!channel) return;

      const state = { autoplay: null, popups: null, held: new Set() };
      window.__linenSiteGuard = state;

      let touched = false;
      const notice = () => { touched = true; };
      for (const kind of ['pointerdown', 'keydown', 'touchstart']) {
        document.addEventListener(kind, notice, { capture: true, passive: true });
      }
      const startedByHand = () => {
        const activation = navigator.userActivation;
        return activation ? activation.hasBeenActive : touched;
      };

      const guard = (event) => {
        const media = event.target;
        if (!(media instanceof HTMLMediaElement)) return;
        if (state.autoplay === 'allow' || startedByHand()) return;
        if (state.autoplay === null) {
          state.held.add(media);
          media.pause();
          return;
        }
        if (state.autoplay === 'block') {
          media.pause();
          return;
        }
        if (state.autoplay === 'silent' && !media.muted) {
          media.muted = true;
        }
      };
      document.addEventListener('play', guard, true);

      const release = () => {
        for (const media of state.held) {
          if (state.autoplay === 'block') continue;
          if (state.autoplay === 'silent') media.muted = true;
          const resumed = media.play();
          if (resumed && resumed.catch) resumed.catch(() => {});
        }
        state.held.clear();
      };

      const opener = window.open;
      window.open = function (...args) {
        const opened = opener.apply(window, args);
        if (!opened && state.popups === 'blockAndNotify') {
          try {
            const wanted = args[0] === undefined ? '' : String(args[0]);
            channel.postMessage({ blocked: new URL(wanted, location.href).href });
          } catch (_) {
            try { channel.postMessage({ blocked: '' }); } catch (_) {}
          }
        }
        return opened;
      };

      const settle = (answer) => {
        state.autoplay = answer && answer.autoplay ? answer.autoplay : 'block';
        state.popups = answer && answer.popups ? answer.popups : 'allow';
        release();
      };
      channel.postMessage({ ask: 'policy' }).then(settle).catch(() => settle(null));
    })();
    """#
}
