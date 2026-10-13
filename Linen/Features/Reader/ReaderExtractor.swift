// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
struct ReaderDriver {
    var probe: () async -> Bool
    var watch: () async -> Bool = { false }
    var extract: () async -> ReaderArticle?

    static func webKit(_ webView: @escaping @MainActor () -> WKWebView?) -> ReaderDriver {
        ReaderDriver(
            probe: {
                guard let webView = webView() else { return false }
                return await ReaderExtractor.isReaderable(webView)
            },
            watch: {
                guard let webView = webView() else { return false }
                return await ReaderExtractor.becomesReaderable(webView, within: .seconds(10))
            },
            extract: {
                guard let webView = webView() else { return nil }
                return await ReaderExtractor.article(in: webView)
            }
        )
    }
}

@MainActor
enum ReaderExtractor {
    static let world = WKContentWorld.world(name: "LinenReader")

    static let replyCeiling: Duration = .seconds(5)

    static func isReaderable(_ webView: WKWebView) async -> Bool {
        await call(probeScript, in: webView, within: replyCeiling)
    }

    static func becomesReaderable(_ webView: WKWebView, within window: Duration) async -> Bool {
        await call(
            watchScript, arguments: ["timeout": Int(window / .milliseconds(1))],
            in: webView, within: window + replyCeiling
        )
    }

    private static func call(
        _ body: String, arguments: [String: Any] = [:], in webView: WKWebView, within ceiling: Duration
    ) async -> Bool {
        guard let document = webView.url, isEligible(document) else { return false }
        let value = await webView.callAsyncJavaScript(
            body, arguments: arguments, in: world, within: ceiling, as: Bool.self
        )
        guard webView.url == document else { return false }
        return value ?? false
    }

    static func article(in webView: WKWebView) async -> ReaderArticle? {
        guard let document = webView.url, isEligible(document) else { return nil }
        let value = await webView.evaluateJavaScript(extractScript, in: world, within: replyCeiling, as: String.self)
        guard webView.url == document,
              let json = value,
              let article = await decode(json),
              webView.url == document,
              article.url.absoluteString == document.absoluteString
        else { return nil }
        return article
    }

    @concurrent
    private nonisolated static func decode(_ json: String) async -> ReaderArticle? {
        ReaderArticle(json: json)
    }

    nonisolated static func isEligible(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }

    private static func source(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    private static let readerableSource = """
    \(source("Readability-readerable"))
    const linenArticleTypes = /^(article|newsarticle|blogposting|reportagenewsarticle|analysisnewsarticle|opinionnewsarticle|reviewnewsarticle|scholarlyarticle|techarticle|liveblogposting)$/i;
    function linenHasArticleMetadata() {
      const og = document.querySelector('meta[property="og:type"]');
      if (og && (og.content || '').trim().toLowerCase() === 'article') return true;
      for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
        let stack;
        try { stack = [JSON.parse(script.textContent)]; } catch (e) { continue; }
        while (stack.length) {
          const item = stack.pop();
          if (Array.isArray(item)) { stack.push(...item); continue; }
          if (!item || typeof item !== 'object') continue;
          const types = [].concat(item['@type'] || []);
          if (types.some(type => typeof type === 'string' && linenArticleTypes.test(type))) return true;
          if (item['@graph']) stack.push(item['@graph']);
        }
      }
      const articles = document.querySelectorAll('article');
      return articles.length === 1 && articles[0].querySelector('time, [rel="author"], [itemprop="author"]') !== null;
    }
    let linenArticleList = false;
    function linenCounts(node) {
      if (linenArticleList && node.tagName === 'ARTICLE') return false;
      if (!isNodeVisible(node)) return false;
      if (node.checkVisibility && !node.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false;
      const rect = node.getBoundingClientRect();
      return rect.width > 1 && rect.height > 1;
    }
    function linenIsReaderable() {
      if (typeof isProbablyReaderable !== 'function') return false;
      linenArticleList = document.querySelectorAll('article').length > 1;
      const metadata = linenHasArticleMetadata();
      if (isProbablyReaderable(document, { visibilityChecker: linenCounts })) {
        const root = location.pathname.replace(/\\/+$/, '') === '' && !location.search;
        return metadata || !root;
      }
      return metadata && isProbablyReaderable(document, { minScore: 10, minContentLength: 100, visibilityChecker: linenCounts });
    }
    """

    private static let probeScript = """
    if (document.readyState === 'loading') {
      await new Promise(resolve => document.addEventListener('DOMContentLoaded', resolve, { once: true }));
    }
    \(readerableSource)
    return linenIsReaderable();
    """

    private static let watchScript = """
    \(readerableSource)
    if (linenIsReaderable()) return true;
    return await new Promise(resolve => {
      let pending = null;
      const finish = value => {
        observer.disconnect();
        clearTimeout(pending);
        clearTimeout(deadline);
        resolve(value);
      };
      const observer = new MutationObserver(() => {
        if (pending) return;
        pending = setTimeout(() => {
          pending = null;
          if (linenIsReaderable()) finish(true);
        }, 500);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
      const deadline = setTimeout(() => finish(false), timeout);
    });
    """

    private static let extractScript = """
    (() => {
    \(source("Readability"))
    if (typeof Readability !== 'function') return '';
    const copy = document.cloneNode(true);
    const parsed = new Readability(copy, { charThreshold: 400 }).parse();
    if (!parsed || !parsed.content) return '';
    const holder = copy.createElement('div');
    holder.innerHTML = parsed.content;
    const removed = 'script, style, link, meta, base, iframe, frame, frameset, object, embed, applet, '
      + 'form, input, button, select, textarea, noscript, template, portal';
    holder.querySelectorAll(removed).forEach(el => el.remove());
    const urlAttributes = ['href', 'src', 'srcset', 'xlink:href', 'action', 'formaction', 'poster', 'data'];
    for (const el of holder.querySelectorAll('*')) {
      for (const attr of Array.from(el.attributes)) {
        const name = attr.name.toLowerCase();
        const value = attr.value.replace(/[\\s\\u0000-\\u001f]/g, '').toLowerCase();
        const scripted = urlAttributes.includes(name) && (value.startsWith('javascript:') || value.startsWith('vbscript:') || value.startsWith('data:text/html'));
        if (name.startsWith('on') || name === 'style' || name === 'srcdoc' || scripted) el.removeAttribute(attr.name);
      }
    }
    holder.querySelectorAll('img').forEach(img => img.setAttribute('loading', 'lazy'));
    const selector = 'p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, figcaption, dt, dd';
    const blocks = [];
    for (const el of holder.querySelectorAll(selector)) {
      if (el.querySelector(selector)) continue;
      const text = (el.textContent || '').replace(/\\s+/g, ' ').trim();
      if (!text) continue;
      el.setAttribute('data-linen-block', String(blocks.length));
      blocks.push(text);
    }
    if (!blocks.length) {
      const text = (parsed.textContent || '').replace(/\\s+/g, ' ').trim();
      if (!text) return '';
      blocks.push(text);
    }
    return JSON.stringify({
      url: location.href,
      title: parsed.title || document.title || '',
      byline: parsed.byline || '',
      siteName: parsed.siteName || '',
      excerpt: parsed.excerpt || '',
      lang: parsed.lang || document.documentElement.lang || '',
      dir: parsed.dir || '',
      content: holder.innerHTML,
      blocks
    });
    })()
    """
}
