// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

enum PageActivityKind: String {
    case editedForm
    case screenShare
}

struct PageActivitySignal: Equatable {
    let kind: PageActivityKind
    let token: String
    let isActive: Bool
}

final class PageActivityMonitor: NSObject, WKScriptMessageHandler {
    static let shared = PageActivityMonitor()

    private static let handlerName = "linenPageActivity"
    private static let maximumTokenLength = 100
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()

    func install(in webView: TabWebView) {
        guard !webView.hasPageActivityMonitor else { return }
        webView.hasPageActivityMonitor = true

        let controller = webView.configuration.userContentController
        guard !installedControllers.contains(controller) else { return }
        installedControllers.add(controller)
        controller.addUserScript(WKUserScript(
            source: Self.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let webView = message.webView as? TabWebView,
              let body = message.body as? [String: Any],
              let rawKind = body["kind"] as? String,
              let kind = PageActivityKind(rawValue: rawKind),
              let token = body["token"] as? String,
              !token.isEmpty,
              token.count <= Self.maximumTokenLength,
              let isActive = body["active"] as? Bool
        else { return }

        webView.onPageActivity?(PageActivitySignal(kind: kind, token: token, isActive: isActive))
    }

    private static let script = #"""
    (() => {
      if (window.__linenPageActivity) return;

      const channel = window.webkit?.messageHandlers?.linenPageActivity;
      if (!channel) return;

      const token = globalThis.crypto?.randomUUID?.()
        || `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const baselines = new WeakMap();
      const dirtyControls = new Set();
      let reportedDirty = false;
      let reportedShare = false;
      const displayTracks = new Set();

      const post = (kind, active) => {
        try { channel.postMessage({ kind, token, active: Boolean(active) }); }
        catch (_) {}
      };

      const controlFor = (target) => {
        if (!(target instanceof Element)) return null;
        return target.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"])');
      };

      const signature = (control) => {
        if (control instanceof HTMLInputElement) {
          if (control.type === 'checkbox' || control.type === 'radio') return `c:${control.checked}`;
          if (control.type === 'file') return `f:${control.files?.length || 0}`;
          return `v:${control.value}`;
        }
        if (control instanceof HTMLTextAreaElement) return `v:${control.value}`;
        if (control instanceof HTMLSelectElement) {
          return Array.from(control.options, option => option.selected ? '1' : '0').join('');
        }
        return `t:${control.textContent || ''}`;
      };

      const remember = (control) => {
        if (control && !baselines.has(control)) baselines.set(control, signature(control));
      };

      const reportDirty = () => {
        for (const control of dirtyControls) {
          if (!control.isConnected) dirtyControls.delete(control);
        }
        const active = dirtyControls.size > 0;
        if (active === reportedDirty) return;
        reportedDirty = active;
        post('editedForm', active);
      };

      const update = (control) => {
        if (!control) return;
        remember(control);
        if (signature(control) === baselines.get(control)) dirtyControls.delete(control);
        else dirtyControls.add(control);
        reportDirty();
      };

      addEventListener('focusin', event => remember(controlFor(event.target)), true);
      addEventListener('beforeinput', event => remember(controlFor(event.target)), true);
      addEventListener('input', event => update(controlFor(event.target)), true);
      addEventListener('change', event => update(controlFor(event.target)), true);

      addEventListener('reset', event => {
        const form = event.target;
        setTimeout(() => {
          if (!(form instanceof HTMLFormElement)) return;
          for (const control of form.querySelectorAll('input, textarea, select, [contenteditable]')) {
            baselines.set(control, signature(control));
            dirtyControls.delete(control);
          }
          reportDirty();
        });
      }, true);

      addEventListener('submit', event => {
        queueMicrotask(() => {
          if (event.defaultPrevented || !(event.target instanceof HTMLFormElement)) return;
          for (const control of event.target.querySelectorAll('input, textarea, select, [contenteditable]')) {
            dirtyControls.delete(control);
          }
          reportDirty();
        });
      }, true);

      const reportShare = () => {
        for (const track of displayTracks) {
          if (track.readyState === 'ended') displayTracks.delete(track);
        }
        const active = displayTracks.size > 0;
        if (active === reportedShare) return;
        reportedShare = active;
        post('screenShare', active);
      };

      const mediaDevices = navigator.mediaDevices;
      const originalDisplayMedia = mediaDevices?.getDisplayMedia;
      if (typeof originalDisplayMedia === 'function') {
        try {
          mediaDevices.getDisplayMedia = async function (...args) {
            const stream = await originalDisplayMedia.apply(this, args);
            for (const track of stream.getVideoTracks()) {
              displayTracks.add(track);
              track.addEventListener('ended', () => {
                displayTracks.delete(track);
                reportShare();
              }, { once: true });
            }
            reportShare();
            return stream;
          };
        } catch (_) {}
      }

      addEventListener('pagehide', () => {
        post('editedForm', false);
        post('screenShare', false);
      });
      addEventListener('pageshow', () => {
        post('editedForm', dirtyControls.size > 0);
        reportShare();
      });

      window.__linenPageActivity = true;
    })();
    """#
}

final class ScrollPositionMonitor: NSObject, WKScriptMessageHandler {
    static let shared = ScrollPositionMonitor()

    private static let handlerName = "linenScrollPosition"
    private let installedControllers = NSHashTable<WKUserContentController>.weakObjects()

    func install(in webView: TabWebView) {
        guard !webView.hasScrollPositionMonitor else { return }
        webView.hasScrollPositionMonitor = true

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
        guard let webView = message.webView as? TabWebView,
              message.frameInfo.isMainFrame,
              let y = (message.body as? NSNumber)?.doubleValue,
              y.isFinite, y >= 0
        else { return }
        webView.onScrollPosition?(y)
    }

    private static let script = #"""
    (() => {
      if (window.__linenScrollPosition) return;

      const channel = window.webkit?.messageHandlers?.linenScrollPosition;
      if (!channel) return;

      let reported = -1;
      let scheduled = false;
      const report = () => {
        scheduled = false;
        const y = window.scrollY;
        if (y === reported) return;
        reported = y;
        try { channel.postMessage(y); } catch (_) {}
      };
      addEventListener('scroll', () => {
        if (scheduled) return;
        scheduled = true;
        setTimeout(report, 120);
      }, { passive: true });

      window.__linenScrollPosition = true;
    })();
    """#
}

nonisolated struct ScrollReturnMemory {
    static let topThreshold: Double = 1

    private var offsets: [String: Double] = [:]
    private let capacity: Int

    init(capacity: Int = 400) {
        self.capacity = capacity
    }

    mutating func remember(_ y: Double, leaving url: String?) {
        guard let url, !url.isEmpty else { return }
        if offsets.count >= capacity, offsets[url] == nil {
            offsets.removeAll()
        }
        offsets[url] = y
    }

    func offset(returningTo url: String?) -> Double? {
        guard let url, let y = offsets[url], y > Self.topThreshold else { return nil }
        return y
    }
}
