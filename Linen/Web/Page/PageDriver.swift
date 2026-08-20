// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
enum PageDriver {
    // MARK: - The page-side runtime

    // swiftlint:disable line_length
    private static let runtime = #"""
      const R = (window.__linen = window.__linen || (() => {
      const norm = s => (s || '').replace(/\s+/g, ' ').trim();

      function* walk(root) {
        for (const el of root.querySelectorAll('*')) {
          yield el;
          if (el.shadowRoot) yield* walk(el.shadowRoot);
          if (el.tagName === 'IFRAME') {
            try {
              if (el.contentDocument && el.contentDocument.body) yield* walk(el.contentDocument.body);
            } catch (e) {}
          }
        }
      }

      const visible = el => {
        try { if (el.checkVisibility && !el.checkVisibility()) return false; } catch (e) {}
        return el.getClientRects().length > 0;
      };

      const kindOf = el => {
        const tag = el.tagName;
        if (tag === 'SELECT') return 'select';
        if (tag === 'TEXTAREA') return 'field';
        if (tag === 'INPUT') {
          const t = (el.type || 'text').toLowerCase();
          if (t === 'hidden') return null;
          if (t === 'submit' || t === 'button' || t === 'image') return 'button';
          if (t === 'checkbox') return 'checkbox';
          if (t === 'radio') return 'radio';
          return 'field';
        }
        if (tag === 'BUTTON' || tag === 'SUMMARY') return 'button';
        if (tag === 'A' && el.href) return 'link';
        const role = el.getAttribute && el.getAttribute('role');
        if (['button', 'tab', 'menuitem', 'checkbox', 'radio', 'link', 'option', 'switch'].includes(role)) return 'button';
        if (el.hasAttribute && el.hasAttribute('onclick')) return 'button';
        if (el.isContentEditable && !(el.parentElement && el.parentElement.isContentEditable)) return 'field';
        return null;
      };

      const controlLabel = el => norm(
        el.innerText || el.value || (el.getAttribute && el.getAttribute('aria-label')) || el.title || ''
      ).slice(0, 60);
      const fieldLabel = el => {
        const assoc = el.labels && el.labels.length ? el.labels[0].innerText : '';
        return norm(
          el.placeholder || (el.getAttribute && el.getAttribute('aria-label')) || assoc || el.name || el.id || ''
        ).slice(0, 60);
      };
      const labelOf = (el, kind) => (kind === 'button' || kind === 'link') ? controlLabel(el) : fieldLabel(el);

      const isSensitiveField = el => {
        const kind = ((el.type || '') + '').toLowerCase();
        if (kind === 'password') return true;
        const auto = norm(el.autocomplete).toLowerCase();
        const hint = (fieldLabel(el) + ' ' + auto + ' ' + norm(el.name) + ' ' + norm(el.id)).toLowerCase();
        if (/(?:^| )(?:current-password|new-password|one-time-code|cc-number|cc-exp|cc-exp-month|cc-exp-year|cc-csc|cc-name)(?: |$)/.test(auto)) return true;
        return /password|passcode|\bpin\b|cvv|cvc|cvn|card ?number|cardnumber|card verification|security code|iban|sort ?code|routing|account ?number|ssn|social security|national insurance|passport|tax ?id|one[- ]?time|\botp\b|2fa|verification code|seed phrase|recovery phrase|private key/.test(hint);
      };

      const collect = () => {
        window.__linenRefs = [];
        const out = [];
        for (const el of walk(document.body)) {
          const kind = kindOf(el);
          if (!kind || !visible(el)) continue;
          const label = labelOf(el, kind);
          if (!label && kind !== 'field' && kind !== 'select') continue;
          let dup = false;
          for (let a = el.parentElement, hops = 0; a && hops < 3; a = a.parentElement, hops++) {
            if (a.__linenRef && labelOf(a, 'button') === label) { dup = true; break; }
          }
          if (dup) continue;

          const ref = window.__linenRefs.push(el);
          el.__linenRef = ref;
          const entry = { r: ref, k: kind, l: label };
          if (kind === 'link') entry.h = (el.href || '').slice(0, 200);
          if (kind === 'field') {
            entry.t = ((el.type || (el.isContentEditable ? 'editable' : 'text')) + '').toLowerCase();
            const v = norm(el.value || '');
            if (isSensitiveField(el)) {
              entry.s = 1;
              entry.f = v ? 1 : 0;
            } else if (v) {
              entry.v = v.slice(0, 30);
            }
          }
          if (kind === 'select') {
            entry.v = el.selectedIndex >= 0 ? norm(el.options[el.selectedIndex].text).slice(0, 30) : '';
            entry.o = Array.from(el.options).slice(0, 15).map(o => norm(o.text).slice(0, 30));
          }
          if (kind === 'checkbox' || kind === 'radio') entry.c = el.checked ? 1 : 0;
          if (el.disabled) entry.d = 1;
          out.push(entry);
        }
        return out;
      };

      const pageText = () => {
        let text = document.body ? norm(document.body.innerText) : '';
        for (const frame of document.querySelectorAll('iframe')) {
          try {
            const body = frame.contentDocument && frame.contentDocument.body;
            if (body) { const t = norm(body.innerText); if (t) text += ' ' + t; }
          } catch (e) {}
        }
        return text;
      };

      const viewportText = limit => {
        const height = window.innerHeight;
        const parts = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          const t = norm(node.textContent);
          if (!t) continue;
          const parent = node.parentElement;
          if (!parent) continue;
          const r = parent.getBoundingClientRect();
          if (r.bottom <= 0 || r.top >= height || r.width === 0) continue;
          parts.push(t);
          if (parts.join(' ').length > limit) break;
        }
        const joined = norm(parts.join(' ')).slice(0, limit);
        return joined || pageText().slice(0, limit);
      };

      const resolve = (ref, label, kinds) => {
        if (!window.__linenRefs || !window.__linenRefs.length) collect();
        if (ref > 0) {
          const el = window.__linenRefs[ref - 1];
          if (!el || !el.isConnected) return { stale: true };
          return { el };
        }
        const t = norm(label).toLowerCase();
        const candidates = [];
        for (const el of window.__linenRefs) {
          if (!el.isConnected) continue;
          const kind = kindOf(el);
          if (!kind || !kinds.includes(kind)) continue;
          candidates.push({ el, label: labelOf(el, kind).toLowerCase() });
        }
        const found = candidates.find(c => c.label === t)
          || candidates.find(c => t && c.label.includes(t))
          || candidates.find(c => c.label.length > 2 && t.includes(c.label));
        if (found) return { el: found.el };
        return { options: [...new Set(candidates.map(c => c.label).filter(l => l && l.length < 50))].slice(0, 25) };
      };

      const realm = el => (el.ownerDocument && el.ownerDocument.defaultView) || window;

      const setValue = (el, value) => {
        if (el.isContentEditable) {
          el.focus();
          el.textContent = value;
          el.dispatchEvent(new (realm(el).Event)('input', { bubbles: true }));
          return;
        }
        const view = realm(el);
        const proto = el.tagName === 'TEXTAREA' ? view.HTMLTextAreaElement.prototype : view.HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
        el.dispatchEvent(new (view.Event)('input', { bubbles: true }));
        el.dispatchEvent(new (view.Event)('change', { bubbles: true }));
      };

      const highlight = (el, ms) => {
        try {
          const doc = el.ownerDocument;
          const rect = el.getBoundingClientRect();
          const ring = doc.createElement('div');
          ring.className = '__linen-ring';
          const s = ring.style;
          s.position = 'fixed';
          s.left = (rect.left - 4) + 'px';
          s.top = (rect.top - 4) + 'px';
          s.width = (rect.width + 8) + 'px';
          s.height = (rect.height + 8) + 'px';
          s.border = '2px solid #3478F6';
          s.borderRadius = '7px';
          s.boxShadow = '0 0 0 4px rgba(52, 120, 246, 0.25)';
          s.zIndex = '2147483647';
          s.pointerEvents = 'none';
          s.transition = 'opacity 0.2s';
          doc.body.appendChild(ring);
          setTimeout(() => { s.opacity = '0'; setTimeout(() => ring.remove(), 250); }, ms);
        } catch (e) {}
      };

      const pressEnter = el => {
        const view = realm(el);
        const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true };
        el.dispatchEvent(new (view.KeyboardEvent)('keydown', opts));
        el.dispatchEvent(new (view.KeyboardEvent)('keyup', opts));
        if (el.form) { try { el.form.requestSubmit(); } catch (e) {} }
      };

      return { norm, collect, pageText, viewportText, resolve, setValue, pressEnter, labelOf, kindOf, highlight, isSensitiveField };
    })());
    """#
    // swiftlint:enable line_length

    private static func scripted(_ body: String) -> String {
        "(() => {\n" + runtime + "\n" + body + "\n})()"
    }

    // MARK: - Reading

    static func readRenderedPage(
        _ webView: WKWebView,
        lookingFor: String = "",
        maxTextLength: Int = 2400,
        controlLimit: Int = 40
    ) async -> String {
        await PageSettle.untilIdle(webView)
        await PageSettle.untilQuiet(webView)

        let script = scripted("return JSON.stringify({ text: R.pageText().slice(0, 8000), controls: R.collect() });")
        guard let object = await evaluateJSON(script, in: webView) else {
            return "The page hasn't finished loading. Try again in a moment."
        }

        let fullText = object["text"] as? String ?? ""
        let controls = (object["controls"] as? [[String: Any]]) ?? []
        if fullText.isEmpty, controls.isEmpty {
            return "The page rendered no readable text."
        }

        let text = PageExcerpt.extract(from: fullText, query: lookingFor, budget: maxTextLength)
        var result = "PAGE TEXT:\n\(text)"
        if !controls.isEmpty {
            result += "\n\n" + renderControls(controls, limit: controlLimit)
        }
        return result
    }

    nonisolated struct ListedLink: Equatable, Sendable {
        let label: String
        let url: URL
    }

    nonisolated static let linkArrow = " \u{2192} "

    nonisolated static func listedLinks(in observation: String) -> [ListedLink] {
        var seen = Set<URL>()
        return observation.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("["),
                  let arrow = line.range(of: linkArrow, options: .backwards)
            else { return nil }

            let head = line[..<arrow.lowerBound]
            guard let marker = head.range(of: "] link \""), head.hasSuffix("\"") else { return nil }
            let label = String(head[marker.upperBound..<head.index(before: head.endIndex)])

            var href = line[arrow.upperBound...]
            if let suffix = href.range(of: " (disabled)", options: .backwards),
               suffix.upperBound == href.endIndex {
                href = href[..<suffix.lowerBound]
            }
            guard let url = URL(string: String(href)),
                  url.scheme == "https" || url.scheme == "http",
                  seen.insert(url).inserted
            else { return nil }

            return ListedLink(label: label, url: url)
        }
    }

    static func renderControls(_ controls: [[String: Any]], limit: Int = 40) -> String {
        var lines: [String] = []
        for control in controls.prefix(limit) {
            guard let ref = control["r"] as? Int, let kind = control["k"] as? String else { continue }
            let label = control["l"] as? String ?? ""
            var line = "[\(ref)] \(kind) \"\(label)\""
            switch kind {
            case "link":
                if let href = control["h"] as? String, !href.isEmpty {
                    line += linkArrow + href
                }
            case "field":
                if let type = control["t"] as? String, type != "text" {
                    line += " (\(type))"
                }
                if control["s"] as? Int == 1 {
                    line += (control["f"] as? Int == 1) ? " = (filled, hidden)" : " = (empty)"
                } else if let value = control["v"] as? String {
                    line += " = \"\(value)\""
                }
            case "select":
                if let value = control["v"] as? String, !value.isEmpty {
                    line += " = \"\(value)\""
                }
                if let options = control["o"] as? [String], !options.isEmpty {
                    line += " (options: \(options.joined(separator: " | ")))"
                }
            case "checkbox", "radio":
                line += (control["c"] as? Int == 1) ? " (checked)" : " (unchecked)"
            default:
                break
            }
            if control["d"] as? Int == 1 {
                line += " (disabled)"
            }
            lines.append(line)
        }
        var section = "CONTROLS - pass the [ref] number to clickOnPage, typeOnPage or selectOption:\n"
            + lines.joined(separator: "\n")
        if controls.count > limit {
            section += "\n…and \(controls.count - limit) more. Scroll, or readPage with lookingFor."
        }
        return section
    }

    // MARK: - Actions

    static func click(ref: Int, label: String, in webView: WKWebView, announced: Bool = false) async -> String {
        let resolved = await resolve(ref: ref, label: label, kinds: #"["button","link","checkbox","radio","field","select"]"#, in: webView)
        switch resolved {
        case .failure(let message):
            return message
        case .success(let found):
            if let category = SensitiveAction.category(of: found.label, context: found.context) {
                let permitted = await AgentActionConsent.permit(
                    label: found.label,
                    category: category,
                    host: webView.url?.host(),
                    authoredByAI: AgentAuthoredText.isPresent(in: webView)
                )
                guard permitted else {
                    return SensitiveAction.declined(found.label, category: category)
                }
                if category == .publication {
                    AgentAuthoredText.clear(in: webView)
                }
            }
            if found.disabled {
                return "“\(found.label)” is disabled right now - the page isn't accepting it. Something else may need doing first."
            }
            await announce(ref: found.ref, in: webView, pause: announced)
            let script = scripted("""
              const el = window.__linenRefs[\(found.ref) - 1];
              if (!el || !el.isConnected) { return JSON.stringify({ stale: true }); }
              el.scrollIntoView({ block: 'center' });
              el.click();
              return JSON.stringify({ ok: true });
            """)
            guard let object = await evaluateJSON(script, in: webView), object["ok"] as? Bool == true else {
                return Self.staleMessage
            }
            return "Clicked “\(found.label)”. \(await settleAndSnippet(webView))"
        }
    }

    static func type(
        text: String,
        intoField fieldLabel: String,
        ref: Int,
        submit: Bool,
        in webView: WKWebView,
        announced: Bool = false
    ) async -> String {
        guard let encodedText = jsonString(text) else { return "Could not encode the input." }
        let resolved = await resolve(ref: ref, label: fieldLabel, kinds: #"["field"]"#, in: webView)
        switch resolved {
        case .failure(let message):
            return message
        case .success(let found):
            if submit, let category = SensitiveAction.category(of: found.label, context: found.context) {
                let permitted = await AgentActionConsent.permit(
                    label: found.label,
                    category: category,
                    host: webView.url?.host(),
                    authoredByAI: true
                )
                guard permitted else {
                    return SensitiveAction.declined(found.label, category: category)
                }
            }
            await announce(ref: found.ref, in: webView, pause: announced)
            let script = scripted("""
              const el = window.__linenRefs[\(found.ref) - 1];
              if (!el || !el.isConnected) { return JSON.stringify({ stale: true }); }
              if (R.isSensitiveField(el)) {
                return JSON.stringify({ refused: true });
              }
              el.scrollIntoView({ block: 'center' });
              el.focus();
              R.setValue(el, \(encodedText));
              if (\(submit ? "true" : "false")) { R.pressEnter(el); }
              return JSON.stringify({ ok: true });
            """)
            guard let object = await evaluateJSON(script, in: webView) else {
                return "The page didn't respond to typing."
            }
            if object["refused"] as? Bool == true {
                return "“\(found.label)” looks like a password, payment, or other sensitive field (a code, or an account or ID number). The user has to fill it themselves."
            }
            guard object["ok"] as? Bool == true else { return Self.staleMessage }
            AgentAuthoredText.record(in: webView)
            return "Typed into “\(found.label)”\(submit ? " and submitted" : ""). \(await settleAndSnippet(webView))"
        }
    }

    static func selectOption(
        _ option: String,
        ref: Int,
        field: String,
        in webView: WKWebView,
        announced: Bool = false
    ) async -> String {
        guard let encodedOption = jsonString(option) else { return "Could not encode the option." }
        let resolved = await resolve(ref: ref, label: field, kinds: #"["select"]"#, in: webView)
        switch resolved {
        case .failure(let message):
            return message
        case .success(let found):
            await announce(ref: found.ref, in: webView, pause: announced)
            let script = scripted("""
              const el = window.__linenRefs[\(found.ref) - 1];
              if (!el || !el.isConnected || el.tagName !== 'SELECT') { return JSON.stringify({ stale: true }); }
              const want = R.norm(\(encodedOption)).toLowerCase();
              const options = Array.from(el.options);
              const match = options.find(o => R.norm(o.value).toLowerCase() === want)
                || options.find(o => R.norm(o.text).toLowerCase() === want)
                || options.find(o => R.norm(o.text).toLowerCase().includes(want));
              if (!match) {
                return JSON.stringify({ ok: false, options: options.slice(0, 15).map(o => R.norm(o.text)) });
              }
              for (const o of options) { o.selected = false; }
              match.selected = true;
              el.value = match.value;
              const view = (el.ownerDocument && el.ownerDocument.defaultView) || window;
              el.dispatchEvent(new (view.Event)('input', { bubbles: true }));
              el.dispatchEvent(new (view.Event)('change', { bubbles: true }));
              return JSON.stringify({ ok: true, selected: R.norm(match.text) });
            """)
            guard let object = await evaluateJSON(script, in: webView) else {
                return "The page didn't respond to the selection."
            }
            if object["ok"] as? Bool != true {
                if let options = object["options"] as? [String], !options.isEmpty {
                    return "No option matches “\(option)” in “\(found.label)”. Options: \(options.joined(separator: " | "))"
                }
                return Self.staleMessage
            }
            let selected = object["selected"] as? String ?? option
            return "Selected “\(selected)” in “\(found.label)”. \(await settleAndSnippet(webView))"
        }
    }

    static func scroll(direction: String, in webView: WKWebView) async -> String {
        let delta = direction == "up" ? "-0.8" : "0.8"
        _ = try? await webView.evaluateJavaScript(
            "window.scrollBy({ top: window.innerHeight * \(delta), behavior: 'instant' })"
        )
        await PageSettle.untilQuiet(webView, ceiling: .milliseconds(900))
        return "Scrolled \(direction). Visible now: \(await snippet(of: webView))"
    }

    static func goBack(in webView: WKWebView) async -> String {
        guard webView.canGoBack else { return "There is no page to go back to." }
        webView.goBack()
        await PageSettle.untilIdle(webView)
        await PageSettle.untilQuiet(webView)
        return "Went back. \(await snippet(of: webView))"
    }

    // MARK: - Announcing

    static let announcePause: Duration = .milliseconds(450)

    @TaskLocal static var pauseSleeper: @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }
    private static let ringLife = 1200

    static func announce(ref: Int, in webView: WKWebView, pause: Bool) async {
        let script = scripted("""
          const el = window.__linenRefs[\(ref) - 1];
          if (el && el.isConnected) {
            el.scrollIntoView({ block: 'center' });
            R.highlight(el, \(ringLife));
          }
          return true;
        """)
        _ = try? await webView.evaluateJavaScript(script)
        if pause {
            await pauseSleeper(announcePause)
        }
    }

    // MARK: - Resolution

    private struct Resolved {
        let ref: Int
        let label: String
        let disabled: Bool
        let context: String
    }

    private enum Resolution {
        case success(Resolved)
        case failure(String)
    }

    private static let staleMessage =
        "That element is gone - the page has changed since it was read. Use readPage and act on the fresh refs."

    private static func resolve(ref: Int, label: String, kinds: String, in webView: WKWebView) async -> Resolution {
        guard ref > 0 || !label.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("Say which element: a [ref] number from readPage, or a visible label.")
        }
        guard let encodedLabel = jsonString(label) else { return .failure("Could not encode that label.") }
        let script = scripted("""
          const found = R.resolve(\(ref), \(encodedLabel), \(kinds));
          if (found.stale) { return JSON.stringify({ stale: true }); }
          if (found.options) { return JSON.stringify({ options: found.options }); }
          const el = found.el;
          const kind = R.kindOf(el) || 'button';
          const form = el.form || (el.closest && el.closest('form'));
          const context = R.norm([
            el.getAttribute && el.getAttribute('aria-label'),
            el.title,
            el.name,
            el.getAttribute && el.getAttribute('data-action'),
            el.getAttribute && el.getAttribute('formaction'),
            el.getAttribute && el.getAttribute('onclick'),
            form && form.getAttribute('action'),
            form && form.getAttribute('aria-label'),
            form && form.innerText
          ].filter(Boolean).join(' ')).slice(0, 800);
          return JSON.stringify({
            ref: el.__linenRef || window.__linenRefs.push(el),
            label: R.labelOf(el, kind),
            disabled: el.disabled ? 1 : 0,
            context
          });
        """)
        guard let object = await evaluateJSON(script, in: webView) else {
            return .failure("The page didn't respond. It may still be loading - try readPage.")
        }
        if object["stale"] as? Bool == true {
            return .failure(staleMessage)
        }
        if let options = object["options"] as? [String] {
            return .failure(options.isEmpty
                ? "Nothing on the page matches that. Use readPage to see what's there."
                : "Nothing matches “\(label)”. Present: \(options.joined(separator: " | "))")
        }
        guard let foundRef = object["ref"] as? Int else {
            return .failure("The page didn't respond. It may still be loading - try readPage.")
        }
        return .success(Resolved(
            ref: foundRef,
            label: object["label"] as? String ?? label,
            disabled: object["disabled"] as? Int == 1,
            context: object["context"] as? String ?? ""
        ))
    }

    // MARK: - Helpers

    private static func settleAndSnippet(_ webView: WKWebView) async -> String {
        await PageSettle.afterInteraction(webView)
        return "The page now shows: \(await snippet(of: webView))"
    }

    private static func snippet(of webView: WKWebView) async -> String {
        let script = scripted("return R.viewportText(1200);")
        return (try? await webView.evaluateJavaScript(script)) as? String ?? ""
    }

    private static func evaluateJSON(_ script: String, in webView: WKWebView) async -> [String: Any]? {
        guard let raw = (try? await webView.evaluateJavaScript(script)) as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func jsonString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
