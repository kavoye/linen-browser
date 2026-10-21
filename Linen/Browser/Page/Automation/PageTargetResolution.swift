// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension PageDriver {
    struct Resolved {
        let ref: Int
        let label: String
        let disabled: Bool
        let context: String
        var submits = false
        var isLink = false
    }

    enum Resolution {
        case success(Resolved)
        case failure(String)
    }

    static func wrongKindMessage(
        ref: Int, kind: String, actual: String, requested: String, kinds: String, wanted: String, in webView: WKWebView
    ) async -> String {
        let opening = "[\(ref)] is a \(kind) “\(actual)”, not a \(wanted)."
        if !requested.isEmpty, !labelsAgree(requested, actual) {
            if case .success(let match) = await resolve(ref: 0, label: requested, kinds: kinds, in: webView) {
                return opening + " “\(match.label)” is [\(match.ref)]: use ref \(match.ref)."
            }
            return opening + " Use the ref of a \(wanted) from readPage."
        }
        let hint = toolForKind[kind].map { " To use it, call \($0) with ref \(ref)." } ?? ""
        return opening + hint + " Otherwise use the ref of a \(wanted) from readPage."
    }

    static let toolForKind = [
        "button": "clickOnPage", "link": "clickOnPage", "select": "selectOption", "checkbox": "setChecked",
        "radio": "setChecked", "field": "typeOnPage",
    ]

    static let staleMessage =
        "That element is gone - the page has changed since it was read. Use readPage and act on the fresh refs."

    static func staleMessage(ref: Int, in view: WKWebView) -> String {
        guard let current = observation(in: view), let listed = current.listed(expectedObservation),
            !listed.contains(ref)
        else { return staleMessage }
        let page = view.title.map { $0.isEmpty ? "" : " The page is now “\($0)”." } ?? ""
        return "[\(ref)] was not listed in that observation.\(page) Use a ref it listed, readPage with lookingFor to find the control, or goBack to return to the previous page."
    }

    static func clickRefusal(ref: Int, label: String, found: Resolved, in webView: WKWebView, constraints: AgentRequestConstraints) async -> String? {
        if ref > 0, !labelsAgree(label, found.label) {
            let back = previousPageHint(for: label, in: webView)
            return "[\(ref)] is “\(found.label)”, not “\(label)”. Nothing was clicked." + (back.isEmpty ? " Use the ref listed for the control you mean." : back)
        }
        if let refusal = constraints.refusal(clicking: found.label, submits: found.submits, isLink: found.isLink) {
            return refusal
        }
        return found.submits ? await requestValueRefusal(ref: found.ref, retry: "use “\(found.label)” again", in: webView, constraints: constraints) : nil
    }

    nonisolated static func labelsAgree(_ requested: String, _ actual: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let wanted = words(requested)
        let found = words(actual)
        return wanted.isEmpty || found.isEmpty || !wanted.isDisjoint(with: found)
    }

    static func resolve(ref: Int, label: String, kinds: String, in webView: WKWebView) async -> Resolution {
        guard ref > 0 || !label.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("Say which element: a [ref] number from readPage, or a visible label.")
        }
        if ref > 0, !(await validateObservation(in: webView, ref: ref)) {
            return .failure(staleMessage(ref: ref, in: webView))
        }
        if ref == 0, expectedObservation != nil, !(await validateObservation(in: webView)) {
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
              if (found.wrongKind) { return JSON.stringify({ wrongKind: found.wrongKind, label: found.label }); }
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
                submits: form && ((el.tagName === 'BUTTON' && (el.getAttribute('type') || 'submit') === 'submit')
                  || (el.tagName === 'INPUT' && ['submit', 'image'].includes(el.type))) ? 1 : 0,
                link: kind === 'link' ? 1 : 0,
                context
              });
            """)
        guard let object = await evaluateJSON(script, in: webView) else {
            return .failure("The page didn't respond. It may still be loading - try readPage.")
        }
        if object["stale"] as? Bool == true {
            return .failure(staleMessage)
        }
        if let kind = object["wrongKind"] as? String {
            let wanted = (try? JSONDecoder().decode([String].self, from: Data(kinds.utf8)))?.joined(separator: " or ") ?? "control"
            let actual = object["label"] as? String ?? ""
            return .failure(await wrongKindMessage(ref: ref, kind: kind, actual: actual, requested: label, kinds: kinds, wanted: wanted, in: webView))
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
                context: object["context"] as? String ?? "",
                submits: object["submits"] as? Int == 1,
                isLink: object["link"] as? Int == 1
            ))
    }
}
