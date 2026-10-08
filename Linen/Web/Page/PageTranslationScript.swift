// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated struct PageTranslationSegment: Equatable, Sendable {
    let node: Int
    let text: String
}

nonisolated struct PageTranslationSample: Equatable, Sendable {
    let declaredLanguage: String
    let text: String
}

@MainActor
enum PageTranslationScript {
    static let world = WKContentWorld.world(name: "LinenTranslate")

    static func sample(in webView: WKWebView) async -> PageTranslationSample? {
        let value = try? await call("return api.sample();", in: webView)
        guard let object = value as? [String: Any] else { return nil }
        return PageTranslationSample(
            declaredLanguage: object["lang"] as? String ?? "",
            text: object["text"] as? String ?? ""
        )
    }

    static func start(in webView: WKWebView) async -> Int? {
        let token = (try? await call("return api.start();", in: webView)) as? NSNumber
        return token.map(\.intValue).flatMap { $0 > 0 ? $0 : nil }
    }

    static func next(limit: Int, token: Int, in webView: WKWebView) async -> [[PageTranslationSegment]]? {
        guard let value = try? await call(
            "return await api.next(limit, token);",
            arguments: ["limit": limit, "token": token],
            in: webView
        ), let object = value as? [String: Any], object["done"] as? Bool == false
        else { return nil }
        let blocks = object["blocks"] as? [[[Any]]] ?? []
        return blocks.map { block in
            block.compactMap { pair in
                guard pair.count == 2,
                      let node = (pair[0] as? NSNumber)?.intValue,
                      let text = pair[1] as? String
                else { return nil }
                return PageTranslationSegment(node: node, text: text)
            }
        }
    }

    static func apply(_ texts: [Int: String], in webView: WKWebView) async {
        let pairs = texts.map { [NSNumber(value: $0.key), $0.value] as [Any] }
        _ = try? await call("api.apply(pairs);", arguments: ["pairs": pairs], in: webView)
    }

    static func restore(in webView: WKWebView) async {
        _ = try? await call("api.restore();", in: webView)
    }

    private static func call(
        _ body: String,
        arguments: [String: Any] = [:],
        in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            source + "\nconst api = globalThis.__linenTranslate;\n" + body,
            arguments: arguments,
            in: nil,
            contentWorld: world
        )
    }

    static let source = #"""
    if (!globalThis.__linenTranslate) {
      const skipped = new Set(['script', 'style', 'noscript', 'template', 'code', 'pre', 'kbd', 'samp', 'var',
        'textarea', 'input', 'select', 'option', 'svg', 'math', 'canvas', 'iframe', 'object', 'embed',
        'video', 'audio']);
      const letter = /\p{L}/u;
      const visible = /\S/;
      const displays = new WeakMap();
      let registry = [], queued = new WeakSet(), originals = new Map(), pending = [];
      let active = false, token = 0, observer = null, waiter = null, added = new Set(), flush = null;

      const excluded = el => skipped.has(el.localName) || el.getAttribute('translate') === 'no'
        || el.classList.contains('notranslate') || el.isContentEditable;
      const insideExcluded = node => {
        for (let el = node.parentElement; el; el = el.parentElement) if (excluded(el)) return true;
        return false;
      };
      const isInline = el => {
        let display = displays.get(el);
        if (display === undefined) {
          display = getComputedStyle(el).display;
          displays.set(el, display);
        }
        return display === 'inline' || display === 'contents';
      };
      const blockOf = node => {
        let el = node.parentElement;
        while (el && el !== document.body && isInline(el)) el = el.parentElement;
        return el || document.body;
      };
      const wake = () => {
        const resolve = waiter;
        waiter = null;
        resolve?.();
      };

      const collect = root => {
        if (!root || !active) return;
        if (root.nodeType === Node.ELEMENT_NODE && excluded(root)) return;
        if (insideExcluded(root)) return;
        const open = new Map();
        const consider = node => {
          if (queued.has(node)) return;
          const block = blockOf(node);
          if (!visible.test(node.nodeValue) && !(node.nextSibling && open.has(block))) return;
          queued.add(node);
          let group = open.get(block);
          if (!group) {
            group = { element: block, nodes: [] };
            open.set(block, group);
            pending.push(group);
          }
          group.nodes.push(node);
        };
        if (root.nodeType === Node.TEXT_NODE) {
          consider(root);
          return;
        }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
          acceptNode: node => node.nodeType === Node.TEXT_NODE || node.localName === 'br'
            ? NodeFilter.FILTER_ACCEPT
            : excluded(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP
        });
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (node.nodeType === Node.TEXT_NODE) consider(node);
          else open.delete(blockOf(node));
        }
      };

      const distance = group => {
        const rect = group.element.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return 1e9;
        if (rect.bottom <= 0) return 1e7 - rect.bottom;
        return Math.max(rect.top, 0);
      };

      globalThis.__linenTranslate = {
        sample() {
          const text = (document.body?.innerText || '').slice(0, 4000);
          return { lang: document.documentElement.lang || '', text: (document.title + '\n' + text).trim() };
        },

        start() {
          this.restore();
          if (!document.body) return 0;
          active = true;
          token += 1;
          collect(document.body);
          observer = new MutationObserver(records => {
            for (const record of records) for (const node of record.addedNodes) added.add(node);
            if (flush) return;
            flush = setTimeout(() => {
              flush = null;
              const nodes = [...added];
              added = new Set();
              for (const node of nodes) if (node.isConnected) collect(node);
              for (const node of originals.keys()) if (!node.isConnected) originals.delete(node);
              if (pending.length) wake();
            }, 300);
          });
          observer.observe(document.body, { childList: true, subtree: true });
          return token;
        },

        async next(limit, expected) {
          if (!active || expected !== token) return { done: true };
          if (!pending.length) {
            await new Promise(resolve => {
              waiter = resolve;
              setTimeout(resolve, 60000);
            });
            if (!active || expected !== token) return { done: true };
          }
          pending = pending.filter(group => group.element.isConnected);
          const ranked = pending.map(group => [distance(group), group]).sort((a, b) => a[0] - b[0]);
          const taken = ranked.slice(0, limit).map(entry => entry[1]);
          pending = ranked.slice(limit).map(entry => entry[1]);
          const blocks = [];
          for (const group of taken) {
            const segments = [];
            for (const node of group.nodes) {
              if (!node.isConnected) continue;
              const text = node.nodeValue.replace(/\s+/g, ' ');
              if (!text) continue;
              segments.push([registry.push(new WeakRef(node)) - 1, text]);
            }
            if (segments.some(segment => letter.test(segment[1]))) blocks.push(segments);
          }
          return { done: false, blocks };
        },

        apply(pairs) {
          if (!active) return;
          for (const [index, text] of pairs) {
            const node = registry[index]?.deref();
            registry[index] = undefined;
            if (!node?.isConnected) continue;
            const entry = originals.get(node) || { original: node.nodeValue };
            entry.translated = text;
            originals.set(node, entry);
            node.nodeValue = text;
          }
        },

        restore() {
          active = false;
          observer?.disconnect();
          observer = null;
          clearTimeout(flush);
          flush = null;
          added = new Set();
          for (const [node, entry] of originals) {
            if (node.nodeValue === entry.translated) node.nodeValue = entry.original;
          }
          registry = [];
          queued = new WeakSet();
          originals = new Map();
          pending = [];
          wake();
        }
      };

      addEventListener('pagehide', () => {
        if (!active) return;
        active = false;
        wake();
      });
      addEventListener('pageshow', event => {
        if (event.persisted) globalThis.__linenTranslate.restore();
      });
    }
    """#
}
