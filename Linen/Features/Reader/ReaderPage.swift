// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ReaderPage {
    static let titleBlock = -1

    static func html(
        for article: ReaderArticle,
        typeface: ReaderAppearance.Typeface,
        palette: ReaderAppearance.Palette,
        textSize: Int
    ) -> String {
        let language = article.language.isEmpty ? "" : " lang=\"\(escape(article.language))\""
        let direction = article.isRightToLeft ? "rtl" : "ltr"
        let site = article.siteName.isEmpty ? (article.url.host() ?? "") : article.siteName
        let minutes = String(localized: "\(article.readingMinutes) min read")
        let meta = [article.byline, minutes]
            .filter { !$0.isEmpty }
            .map(escape)
            .joined(separator: " · ")
        return """
        <!doctype html>
        <html\(language) dir="\(direction)" data-typeface="\(typeface.rawValue)" data-palette="\(palette.rawValue)" style="--size: \(textSize)px">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: data:; media-src https: http:; style-src 'unsafe-inline'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(article.title))</title>
        <style>\(typefaceRules)\(stylesheet)</style>
        </head>
        <body>
        <main>
        <header>
        <p class="site">\(escape(site))</p>
        <h1 class="title" id="linen-title">\(escape(article.title))</h1>
        <p class="meta">\(meta)</p>
        </header>
        <article>\(article.content)</article>
        </main>
        </body>
        </html>
        """
    }

    static func appearanceScript(
        typeface: ReaderAppearance.Typeface,
        palette: ReaderAppearance.Palette,
        textSize: Int
    ) -> String {
        """
        (() => {
          const root = document.documentElement;
          root.dataset.typeface = '\(typeface.rawValue)';
          root.dataset.palette = '\(palette.rawValue)';
          root.style.setProperty('--size', '\(textSize)px');
        })()
        """
    }

    static func highlightScript(block: Int?) -> String {
        let selector: String
        switch block {
        case nil:
            selector = ""
        case titleBlock?:
            selector = "#linen-title"
        case let index?:
            selector = "[data-linen-block=\"\(index)\"]"
        }
        return """
        (() => {
          document.querySelectorAll('.linen-speaking').forEach(el => el.classList.remove('linen-speaking'));
          const selector = '\(selector)';
          if (!selector) return;
          const el = document.querySelector(selector);
          if (!el) return;
          el.classList.add('linen-speaking');
          const box = el.getBoundingClientRect();
          if (box.top < 80 || box.bottom > window.innerHeight - 40) {
            el.scrollIntoView({ block: 'center', behavior: 'smooth' });
          }
        })()
        """
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&#39;"
            default:
                result.append(character)
            }
        }
        return result
    }

    private static let typefaceRules = ReaderAppearance.Typeface.allCases
        .map { "html[data-typeface=\"\($0.rawValue)\"] { --face: \($0.cssFamily); }\n" }
        .joined()

    private static let stylesheet = """
    html[data-palette="light"], html[data-palette="automatic"] {
      --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --link: #0066cc;
      --rule: rgba(0, 0, 0, 0.1); --mark: rgba(255, 204, 0, 0.28); color-scheme: light;
    }
    html[data-palette="sepia"] {
      --bg: #f8f1e3; --fg: #4f3b26; --muted: #8a7457; --link: #9b5b1f;
      --rule: rgba(79, 59, 38, 0.14); --mark: rgba(201, 140, 40, 0.24); color-scheme: light;
    }
    html[data-palette="dark"] {
      --bg: #1e1e20; --fg: #e5e5e7; --muted: #98989d; --link: #4ea1ff;
      --rule: rgba(255, 255, 255, 0.12); --mark: rgba(255, 214, 10, 0.2); color-scheme: dark;
    }
    @media (prefers-color-scheme: dark) {
      html[data-palette="automatic"] {
        --bg: #1e1e20; --fg: #e5e5e7; --muted: #98989d; --link: #4ea1ff;
        --rule: rgba(255, 255, 255, 0.12); --mark: rgba(255, 214, 10, 0.2); color-scheme: dark;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; background: var(--bg); color: var(--fg);
      font-family: var(--face); font-size: var(--size); line-height: 1.6;
      -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
      overflow-wrap: break-word;
    }
    main { max-width: 680px; margin: 0 auto; padding: 76px 32px 140px; }
    header .site {
      margin: 0; font: 600 12px/1.3 -apple-system, system-ui, sans-serif;
      letter-spacing: 0.04em; text-transform: uppercase; color: var(--muted);
    }
    h1.title { font-size: 1.85em; line-height: 1.15; margin: 0.35em 0 0.4em; font-weight: 700; }
    header .meta {
      margin: 0 0 2em; padding-bottom: 1.4em; border-bottom: 1px solid var(--rule);
      font: 13px/1.4 -apple-system, system-ui, sans-serif; color: var(--muted);
    }
    article h1, article h2, article h3, article h4 { line-height: 1.25; margin: 1.6em 0 0.5em; }
    article h1 { font-size: 1.4em; }
    article h2 { font-size: 1.25em; }
    article h3 { font-size: 1.1em; }
    img, video, svg, picture { max-width: 100%; height: auto; }
    img { border-radius: 6px; }
    figure { margin: 1.6em 0; }
    figcaption { margin-top: 0.5em; font-size: 0.8em; color: var(--muted); }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.85em; }
    pre { overflow-x: auto; padding: 1em; background: var(--rule); border-radius: 8px; }
    blockquote { margin: 1.4em 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--muted); }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    td, th { border: 1px solid var(--rule); padding: 0.3em 0.6em; }
    hr { border: 0; border-top: 1px solid var(--rule); margin: 2em 0; }
    [data-linen-block], #linen-title { border-radius: 4px; transition: background-color 0.2s, box-shadow 0.2s; }
    .linen-speaking { background: var(--mark); box-shadow: 0 0 0 4px var(--mark); }
    """
}
