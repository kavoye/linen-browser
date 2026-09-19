// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
enum PageDriver {
    // MARK: - The page-side runtime

    static func scripted(_ body: String) -> String {
        "(() => {\n" + PageAutomationGuard.scriptCheck + PageRuntime.script + "\n" + body + "\n})()"
    }

    // MARK: - Reading

    static func readRenderedPage(
        _ webView: WKWebView,
        lookingFor: String = "",
        maxTextLength: Int = 2400,
        controlLimit: Int = 40,
        textOffset: Int = 0,
        controlOffset: Int = 0,
        scope: String = "",
        viewportOnly: Bool = false
    ) async -> String {
        await PageSettle.untilIdle(webView)
        await PageSettle.untilQuiet(webView)
        return await snapshot(
            webView, lookingFor: lookingFor, textLimit: maxTextLength,
            controlLimit: controlLimit, textOffset: textOffset, controlOffset: controlOffset,
            scope: scope, viewportOnly: viewportOnly)
    }

    static func snapshot(
        _ webView: WKWebView, lookingFor: String = "", textLimit: Int? = nil, controlLimit: Int? = nil,
        textOffset: Int = 0, controlOffset: Int = 0, scope: String = "", viewportOnly: Bool = false
    ) async -> String {
        let textLength = max(0, min(textLimit ?? outputBudget.textCharacters, outputBudget.textCharacters))
        let count = max(1, min(controlLimit ?? outputBudget.controls, outputBudget.controls))
        guard let query = jsonString(lookingFor), let selector = jsonString(scope) else { return "Invalid page query." }
        let script = scripted(
            "return JSON.stringify(R.observe(\(query), \(textLength), \(count), \(max(0, textOffset)), \(max(0, controlOffset)), \(selector), \(viewportOnly)));"
        )
        guard let object = await evaluateJSON(script, in: webView) else {
            return "The page did not respond. Use readPage after it finishes loading."
        }
        if let error = object["error"] as? String { return error }
        guard let id = object["snapshot"] as? String, let documentID = object["document"] as? String,
            let url = object["url"] as? String
        else { return "The page changed. Use readPage again." }
        let controls = object["controls"] as? [[String: Any]] ?? []
        let available = max(300, outputBudget.totalCharacters - 650)
        let text = PageOutputBudget.prefix(object["text"] as? String ?? "", fitting: min(textLength, available / 2))
        var result = "PAGE TEXT:\n\(text)\n\nCONTROLS:\n"
        var refs = Set<Int>()
        for control in controls {
            var row = renderControl(control)
            guard !row.isEmpty, let ref = control["r"] as? Int else { continue }
            if refs.isEmpty && PageOutputBudget.cost(result + row) > available {
                var summary = control
                summary["h"] = nil
                summary["o"] = nil
                row = renderControl(summary)
            }
            guard PageOutputBudget.cost(result + row + "\n") <= available else { break }
            result += row + "\n"
            refs.insert(ref)
        }
        let totalText = object["textTotal"] as? Int ?? 0
        let start = object["textStart"] as? Int ?? 0
        let nextText = start + text.utf16.count
        let totalControls = object["controlTotal"] as? Int ?? 0
        let nextControl = max(0, controlOffset) + refs.count
        result += "\nobservationID: \(id)"
        if nextText < totalText {
            result += "\nMore text: readPage textOffset=\(nextText) (\(totalText) UTF-16 units total)."
        }
        if nextControl < totalControls {
            result += "\nMore controls: readPage controlOffset=\(nextControl) (\(totalControls) total); keep the same query and scope."
        }
        observations.setObject(PageObservation(id: id, documentID: documentID, url: url, refs: refs), forKey: webView)
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
        let lines = controls.prefix(limit).map(renderControl).filter { !$0.isEmpty }
        return "CONTROLS:\n" + lines.joined(separator: "\n")
    }

    private static func renderControl(_ control: [String: Any]) -> String {
        guard let ref = control["r"] as? Int, let kind = control["k"] as? String else { return "" }
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
            if control["s"] as? Int == 1 {
                line += (control["f"] as? Int == 1) ? " = (filled, hidden)" : " = (empty)"
            } else if let value = control["v"] as? String, !value.isEmpty {
                line += " = \"\(value)\""
            }
            if let options = control["o"] as? [String], !options.isEmpty {
                line += " (options: \(options.joined(separator: " | ")))"
                if let total = control["oc"] as? Int, total > options.count {
                    line += " (\(total) options; inspectControl for more)"
                }
            }
        case "checkbox", "radio":
            line += (control["c"] as? Int == 1) ? " (checked)" : " (unchecked)"
        default:
            break
        }
        if control["d"] as? Int == 1 {
            line += " (disabled)"
        }
        return line
    }

    // MARK: - Actions

    static func click(ref: Int, label: String, in webView: WKWebView, announced: Bool = false) async -> String {
        let resolved = await resolve(ref: ref, label: label, kinds: #"["button","link","checkbox","radio","field","select","combobox"]"#, in: webView)
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
                guard PageAutomationGuard.allowsExecution else { return Self.staleMessage }
                if category == .publication {
                    AgentAuthoredText.clear(in: webView)
                }
            }
            if found.disabled {
                return "“\(found.label)” is disabled right now - the page isn't accepting it. Something else may need doing first."
            }
            await announce(ref: found.ref, in: webView, pause: announced)
            if let error = await prepareAction(ref: found.ref, in: webView) {
                return error
            }
            let script = scripted(
                """
                  const el = window.__linenRefs[\(found.ref) - 1];
                  if (!el || !el.isConnected) { return JSON.stringify({ stale: true }); }
                  const error = R.actionable(el);
                  if (error) return JSON.stringify({ error });
                  el.click();
                  return JSON.stringify({ ok: true });
                """)
            guard let object = await evaluateJSON(script, in: webView) else { return staleMessage }
            if let error = object["error"] as? String { return error }
            guard object["ok"] as? Bool == true else { return staleMessage }
            return "Clicked “\(found.label)”. \(await settleAndSnippet(webView))"
        }
    }

    static func type(
        text: String,
        intoField fieldLabel: String,
        ref: Int,
        submit: Bool,
        in webView: WKWebView,
        announced: Bool = false,
        refreshControls: Bool = true
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
            if let error = await prepareAction(ref: found.ref, in: webView) {
                return error
            }
            let script = scripted(
                """
                  const el = window.__linenRefs[\(found.ref) - 1];
                  if (!el || !el.isConnected) { return JSON.stringify({ stale: true }); }
                  if (R.isSensitiveField(el)) {
                    return JSON.stringify({ refused: true });
                  }
                  if (R.disabled(el) || el.readOnly) { return JSON.stringify({ unavailable: true }); }
                  if (!['INPUT','TEXTAREA'].includes(el.tagName) && !el.isContentEditable) return JSON.stringify({ error: 'This control is not directly editable. Use click or keyboard controls.' });
                  if (el.tagName === 'INPUT' && ['file','range','color','hidden','checkbox','radio','button','submit'].includes(el.type)) {
                    return JSON.stringify({ error: 'Use the appropriate control tool for this input type.' });
                  }
                  const error = R.actionable(el);
                  if (error) return JSON.stringify({ error });
                  el.scrollIntoView({ block: 'center' });
                  el.focus();
                  R.expectValue(el, \(encodedText));
                  R.setValue(el, \(encodedText));
                  const retained = R.valueState(\(found.ref)) === 'matched';
                  if (\(submit ? "true" : "false") && retained) { R.pressEnter(el); }
                  return JSON.stringify({ ok: true, submitted: \(submit ? "true" : "false") && retained });
                """)
            guard let object = await evaluateJSON(script, in: webView) else {
                return "The page didn't respond to typing."
            }
            if let error = object["error"] as? String { return error }
            if object["unavailable"] as? Bool == true {
                return "The field is disabled or read-only. Read the page for available controls."
            }
            if object["refused"] as? Bool == true {
                return
                    "“\(found.label)” looks like a password, payment, or other sensitive field (a code, or an account or ID number). The user has to fill it themselves."
            }
            guard object["ok"] as? Bool == true else { return Self.staleMessage }
            AgentAuthoredText.record(in: webView)
            let submitted = object["submitted"] as? Bool == true
            let status = submit && !submitted
                ? "The field did not retain the requested value; submission was not attempted. Inspect the current page before retrying."
                : "Typed into “\(found.label)”\(submitted ? " and requested submission" : "")."
            return await finishValueAction(
                status: status, ref: found.ref, documentID: observation(in: webView)?.documentID,
                submissionRequested: submitted, refreshControls: refreshControls, in: webView)
        }
    }

    static func selectOption(
        _ option: String,
        ref: Int,
        field: String,
        in webView: WKWebView,
        announced: Bool = false,
        refreshControls: Bool = true
    ) async -> String {
        guard let encodedOption = jsonString(option) else { return "Could not encode the option." }
        let resolved = await resolve(ref: ref, label: field, kinds: #"["select"]"#, in: webView)
        switch resolved {
        case .failure(let message):
            return message
        case .success(let found):
            await announce(ref: found.ref, in: webView, pause: announced)
            if let error = await prepareAction(ref: found.ref, in: webView) {
                return error
            }
            let script = scripted(
                """
                  const el = window.__linenRefs[\(found.ref) - 1];
                  if (!el || !el.isConnected || el.tagName !== 'SELECT') { return JSON.stringify({ stale: true }); }
                  if (R.isSensitiveField(el)) { return JSON.stringify({ refused: true }); }
                  const error = R.actionable(el);
                  if (error) return JSON.stringify({ error });
                  const want = R.norm(\(encodedOption)).toLowerCase();
                  const options = Array.from(el.options);
                  let matches = options.filter(o => R.norm(o.value).toLowerCase() === want);
                  if (!matches.length) matches = options.filter(o => R.norm(o.text).toLowerCase() === want);
                  if (!matches.length) matches = options.filter(o => R.norm(o.text).toLowerCase().includes(want));
                  if (matches.length > 1) return JSON.stringify({ error: 'Several options match. Inspect the control and use an exact value or label.' });
                  const match = matches[0];
                  if (!match) {
                    return JSON.stringify({ ok: false, options: options.slice(0, 8).map(o => R.norm(o.text).slice(0, 60)) });
                  }
                  if (match.disabled || match.closest('optgroup[disabled]')) return JSON.stringify({ error: 'That option is disabled.' });
                  R.expectValue(el, match.value);
                  for (const o of options) { o.selected = false; }
                  match.selected = true;
                  el.value = match.value;
                  const view = (el.ownerDocument && el.ownerDocument.defaultView) || window;
                  el.dispatchEvent(new (view.Event)('input', { bubbles: true }));
                  el.dispatchEvent(new (view.Event)('change', { bubbles: true }));
                  return JSON.stringify({ ok: true, selected: R.norm(match.text).slice(0, 120) });
                """)
            guard let object = await evaluateJSON(script, in: webView) else {
                return "The page didn't respond to the selection."
            }
            if let error = object["error"] as? String { return error }
            if object["refused"] as? Bool == true {
                return "“\(found.label)” is a sensitive payment field. The user has to fill it themselves."
            }
            if object["ok"] as? Bool != true {
                if let options = object["options"] as? [String], !options.isEmpty {
                    return PageOutputBudget.prefix("No option matches “\(option)” in “\(found.label)”. Options: \(options.joined(separator: " | "))", fitting: outputBudget.totalCharacters - 100)
                }
                return Self.staleMessage
            }
            let selected = PageOutputBudget.prefix(object["selected"] as? String ?? option, fitting: 120)
            let status = "Selected “\(selected)” in “\(found.label)”."
            return await finishValueAction(
                status: status, ref: found.ref, documentID: observation(in: webView)?.documentID,
                refreshControls: refreshControls, in: webView)
        }
    }

    nonisolated struct FieldValue: Codable, Equatable, Sendable {
        let ref: Int
        let value: String
        let select: Bool
    }

    static func fillFields(_ fields: [FieldValue], in webView: WKWebView, announced: Bool = false) async -> String {
        guard (1...8).contains(fields.count), fields.allSatisfy({ $0.ref > 0 }),
            Set(fields.map(\.ref)).count == fields.count
        else {
            return "Use one to eight distinct field refs from the latest page observation."
        }
        guard let initial = await batchState(in: webView) else { return staleMessage }
        let documentID = observation(in: webView)?.documentID
        var completed = 0
        var reason = ""
        for field in fields {
            guard !Task.isCancelled, PageAutomationGuard.allowsExecution,
                !webView.isLoading, await batchState(in: webView) == initial
            else {
                reason = "The page changed. Read the fresh controls before filling remaining fields."
                break
            }
            let result: String
            if field.select {
                result = await selectOption(
                    field.value, ref: field.ref, field: "", in: webView,
                    announced: announced && completed == 0, refreshControls: false)
            } else {
                result = await type(
                    text: field.value, intoField: "", ref: field.ref, submit: false,
                    in: webView, announced: announced && completed == 0, refreshControls: false)
            }
            guard result.hasPrefix("Typed") || result.hasPrefix("Selected") else {
                reason = result
                break
            }
            completed += 1
        }
        await PageSettle.afterInteraction(webView)
        var retained = 0
        for field in fields.prefix(completed) {
            let state = await valueState(ref: field.ref, documentID: documentID, in: webView)
            retained += state == "matched" ? 1 : 0
        }
        if retained < completed {
            reason = "Some earlier values changed or could not be verified. Inspect the current page before retrying. " + reason
            completed = retained
        }
        return "Filled \(completed) of \(fields.count) fields. \(reason)\n" + (await PageAutomationGuard.withCurrentDocument(in: webView) {
            await snapshot(webView)
        })
    }

    private static func batchState(in webView: WKWebView) async -> String? {
        guard PageAutomationGuard.allowsExecution else { return nil }
        let script = scripted(
            """
            const textOutsideFields = doc => {
              if (!doc.body) return '';
              const parts = [];
              const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
              let node;
              while ((node = walker.nextNode())) {
                const parent = node.parentElement;
                if (!parent || parent.isContentEditable || parent.closest('textarea,script,style,noscript')) continue;
                if (!parent.getClientRects().length || (parent.checkVisibility && !parent.checkVisibility())) continue;
                parts.push(node.textContent);
              }
              return R.norm(parts.join(' '));
            };
            const markupWithoutValues = el => {
              const copy = el.cloneNode(true);
              if (el.isContentEditable || el.tagName === 'TEXTAREA') copy.replaceChildren();
              for (const field of copy.querySelectorAll('textarea,[contenteditable]:not([contenteditable="false"])')) {
                field.replaceChildren();
              }
              return copy.outerHTML.replace(/value="[^"]*"/g, '');
            };
            let text = textOutsideFields(document);
            for (const frame of document.querySelectorAll('iframe')) {
              try { if (frame.contentDocument) text += ' ' + textOutsideFields(frame.contentDocument); } catch (e) {}
            }
            return JSON.stringify({ snapshot: window.__linenSnapshot, url: location.href,
              text, refs: (window.__linenRefs || []).map(el =>
                [el.isConnected, el.disabled, R.kindOf(el), el.name, el.id, markupWithoutValues(el)]) });
            """)
        return (try? await webView.evaluateJavaScript(script, in: nil, contentWorld: PageAutomationGuard.world)) as? String
    }

    static func scroll(direction: String, ref: Int = 0, in webView: WKWebView) async -> String {
        guard ["up", "down", "left", "right"].contains(direction) else { return "Use up, down, left, or right." }
        guard PageAutomationGuard.allowsExecution else { return staleMessage }
        if ref > 0, !(await validateObservation(in: webView, ref: ref)) {
            return staleMessage
        }
        let horizontal = direction == "left" || direction == "right"
        let sign = direction == "up" || direction == "left" ? -1 : 1
        let script = scripted(
            """
            let el = \(ref) > 0 ? window.__linenRefs[\(ref) - 1] : document.scrollingElement;
            const horizontal = \(horizontal);
            const canScroll = e => horizontal ? e.scrollWidth > e.clientWidth + 1 : e.scrollHeight > e.clientHeight + 1;
            while (el && !canScroll(el)) el = el.parentElement || el.getRootNode()?.host;
            if (!el) return JSON.stringify({ error: 'No scrollable container in that direction.' });
            const before = horizontal ? el.scrollLeft : el.scrollTop;
            el.scrollBy({ left: horizontal ? el.clientWidth * 0.8 * \(sign) : 0,
              top: horizontal ? 0 : el.clientHeight * 0.8 * \(sign), behavior: 'instant' });
            const after = horizontal ? el.scrollLeft : el.scrollTop;
            return JSON.stringify({ moved: Math.abs(after - before) > 0.5 });
            """)
        guard let result = await evaluateJSON(script, in: webView) else { return staleMessage }
        if let error = result["error"] as? String { return error }
        await PageSettle.untilQuiet(webView, ceiling: .milliseconds(900))
        let status = result["moved"] as? Bool == true ? "Scrolled \(direction)." : "Already at the \(direction) scroll boundary."
        return status + "\n" + (await PageAutomationGuard.withCurrentDocument(in: webView) {
            await snapshot(webView, viewportOnly: ref == 0)
        })
    }

    static func goBack(in webView: WKWebView) async -> String {
        guard PageAutomationGuard.allowsExecution else { return staleMessage }
        guard webView.canGoBack else { return "There is no page to go back to." }
        webView.goBack()
        return "Went back. " + (await settleAndSnippet(webView))
    }

    // MARK: - Announcing

    static let announcePause: Duration = .milliseconds(450)

    @TaskLocal static var pauseSleeper: @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }
    private static let ringLife = 1200

    static func announce(ref: Int, in webView: WKWebView, pause: Bool) async {
        guard PageAutomationGuard.allowsExecution else { return }
        let script = scripted(
            """
              const el = window.__linenRefs[\(ref) - 1];
              if (el && el.isConnected) {
                el.scrollIntoView({ block: 'center' });
                R.highlight(el, \(ringLife));
              }
              return true;
            """)
        _ = try? await webView.evaluateJavaScript(script, in: nil, contentWorld: PageAutomationGuard.world)
        if pause {
            await pauseSleeper(announcePause)
        }
    }

    // MARK: - Resolution

    struct Resolved {
        let ref: Int
        let label: String
        let disabled: Bool
        let context: String
    }

    enum Resolution {
        case success(Resolved)
        case failure(String)
    }

    static let staleMessage =
        "That element is gone - the page has changed since it was read. Use readPage and act on the fresh refs."

    static func resolve(ref: Int, label: String, kinds: String, in webView: WKWebView) async -> Resolution {
        guard ref > 0 || !label.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("Say which element: a [ref] number from readPage, or a visible label.")
        }
        if ref > 0, !(await validateObservation(in: webView, ref: ref)) {
            return .failure(staleMessage)
        }
        if ref == 0, expectedObservation == nil {
            _ = await snapshot(webView, lookingFor: label)
        }
        guard let encodedLabel = jsonString(label) else { return .failure("Could not encode that label.") }
        let script = scripted(
            """
              const found = R.resolve(\(ref), \(encodedLabel), \(kinds));
              if (found.stale) { return JSON.stringify({ stale: true }); }
              if (found.ambiguous) { return JSON.stringify({ ambiguous: true }); }
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
                disabled: R.disabled(el) ? 1 : 0,
                context
              });
            """)
        guard let object = await evaluateJSON(script, in: webView) else {
            return .failure("The page didn't respond. It may still be loading - try readPage.")
        }
        if object["stale"] as? Bool == true {
            return .failure(staleMessage)
        }
        if object["ambiguous"] as? Bool == true {
            return .failure("Several controls match. Use readPage and choose a specific ref.")
        }
        if let options = object["options"] as? [String] {
            let message = options.isEmpty
                ? "Nothing on the page matches that. Use readPage to see what's there."
                : "Nothing matches “\(label)”. Present: \(options.joined(separator: " | "))"
            return .failure(PageOutputBudget.prefix(message, fitting: outputBudget.totalCharacters - 100))
        }
        guard let foundRef = object["ref"] as? Int else {
            return .failure("The page didn't respond. It may still be loading - try readPage.")
        }
        return .success(
            Resolved(
                ref: foundRef,
                label: object["label"] as? String ?? label,
                disabled: object["disabled"] as? Int == 1,
                context: object["context"] as? String ?? ""
            ))
    }

    // MARK: - Helpers

    static func settleAndSnippet(_ webView: WKWebView, refreshControls: Bool = true) async -> String {
        await PageSettle.afterInteraction(webView)
        guard refreshControls else { return "The page now shows: \(await snippet(of: webView))" }
        return await PageAutomationGuard.withCurrentDocument(in: webView) {
            await snapshot(webView)
        }
    }

    private static func snippet(of webView: WKWebView) async -> String {
        guard PageAutomationGuard.allowsExecution else { return "" }
        let script = scripted("return R.viewportText(1200);")
        let text = (try? await webView.evaluateJavaScript(script, in: nil, contentWorld: PageAutomationGuard.world)) as? String ?? ""
        return PageAutomationGuard.allowsExecution ? text : ""
    }

    static func evaluateJSON(_ script: String, in webView: WKWebView) async -> [String: Any]? {
        guard PageAutomationGuard.allowsExecution,
            let raw = (try? await webView.evaluateJavaScript(script, in: nil, contentWorld: PageAutomationGuard.world)) as? String,
            PageAutomationGuard.allowsExecution,
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    static func automationSnapshot(in webView: WKWebView) async -> String? {
        guard PageAutomationGuard.allowsExecution else { return nil }
        return
            (try? await webView.evaluateJavaScript(
                "window.__linenSnapshot", in: nil, contentWorld: PageAutomationGuard.world
            )) as? String
    }

    static func jsonString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
