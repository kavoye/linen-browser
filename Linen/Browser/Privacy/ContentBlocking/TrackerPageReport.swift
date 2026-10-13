// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
enum TrackerPageReport {
    static func matchingDomains(in webView: WKWebView) async -> [String] {
        let topLevelURL = webView.url
        guard let value = try? await webView.callAsyncJavaScript(
            resourceURLScript,
            in: nil,
            contentWorld: .defaultClient
        ), let resourceURLs = value as? [String]
        else { return [] }
        guard !Task.isCancelled, webView.url == topLevelURL else { return [] }

        return TrackerList.matchingDomains(
            in: resourceURLs,
            topLevelURL: topLevelURL
        )
    }

    private static let resourceURLScript = #"""
    const found = new Set();

    const add = raw => {
      if (typeof raw !== 'string' || raw.length === 0) return;
      try { found.add(new URL(raw, document.baseURI).href); }
      catch (_) {}
    };

    try {
      for (const entry of performance.getEntriesByType('resource')) add(entry.name);
    } catch (_) {}

    const attributes = [
      ['script[src]', 'src'],
      ['link[href]', 'href'],
      ['img[src]', 'src'],
      ['iframe[src]', 'src'],
      ['source[src]', 'src'],
      ['video[src]', 'src'],
      ['video[poster]', 'poster'],
      ['audio[src]', 'src'],
      ['track[src]', 'src'],
      ['embed[src]', 'src'],
      ['object[data]', 'data'],
      ['input[src]', 'src']
    ];

    for (const [selector, attribute] of attributes) {
      for (const element of document.querySelectorAll(selector)) add(element.getAttribute(attribute));
    }

    for (const element of document.querySelectorAll('[srcset]')) {
      for (const candidate of element.getAttribute('srcset').split(',')) {
        add(candidate.trim().split(/\s+/, 1)[0]);
      }
    }

    const addCSSURLs = text => {
      if (typeof text !== 'string') return;
      for (const match of text.matchAll(/url\(\s*(['"]?)(.*?)\1\s*\)/gi)) add(match[2]);
    };

    for (const element of document.querySelectorAll('[style]')) addCSSURLs(element.getAttribute('style'));
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) addCSSURLs(rule.cssText);
      } catch (_) {}
    }

    return Array.from(found).slice(0, 4000);
    """#
}
