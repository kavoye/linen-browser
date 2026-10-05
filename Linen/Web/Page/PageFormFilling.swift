// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension PageDriver {
    nonisolated struct FieldValue: Codable, Equatable, Sendable {
        let ref: Int
        let value: String
        let select: Bool
    }

    static func fillFields(_ fields: [FieldValue], in webView: WKWebView, announced: Bool = false) async -> String {
        guard (1...32).contains(fields.count), fields.allSatisfy({ $0.ref > 0 }),
            Set(fields.map(\.ref)).count == fields.count
        else {
            return "Use one to 32 distinct field refs from the latest page observation."
        }
        guard let initial = await batchState(in: webView) else { return staleMessage }
        let documentID = observation(in: webView)?.documentID
        var completed: [FieldValue] = []
        var details: [String] = []
        for (index, field) in fields.enumerated() {
            guard !Task.isCancelled, PageAutomationGuard.allowsExecution,
                !webView.isLoading, await batchState(in: webView) == initial,
                await validateObservation(in: webView, ref: field.ref)
            else {
                details.append("The page changed. Read the fresh controls before filling remaining fields.")
                break
            }
            let control = await evaluateJSON(scripted("""
                const el = window.__linenRefs[\(field.ref) - 1];
                return JSON.stringify({ kind: R.kindOf(el), type: el.type,
                  sensitive: R.isSensitiveField(el), unavailable: R.disabled(el) || el.readOnly });
                """), in: webView)
            guard let control else {
                details.append("Could not inspect [\(field.ref)]. Read the page before continuing.")
                break
            }
            if control["sensitive"] as? Bool == true {
                details.append("[\(field.ref)] skipped: sensitive field; the user must fill it. Do not retry with another tool.")
                continue
            }
            if control["unavailable"] as? Bool == true {
                details.append("[\(field.ref)] skipped: disabled or read-only.")
                continue
            }
            if control["type"] as? String == "file" {
                details.append("[\(field.ref)] skipped: use chooseFilesOnPage; file selection requires the user.")
                continue
            }
            let result: String
            let kind = control["kind"] as? String
            if kind == "checkbox" || kind == "radio" {
                guard let checked = Bool(field.value.lowercased()) else {
                    details.append("[\(field.ref)] skipped: use true or false for a checked state.")
                    continue
                }
                result = await setChecked(ref: field.ref, checked: checked, in: webView,
                                          announced: announced && index == 0, refreshControls: false)
            } else if field.select || kind == "select" {
                result = await selectOption(field.value, ref: field.ref, field: "", in: webView,
                                            announced: announced && index == 0, refreshControls: false)
            } else {
                result = await type(text: field.value, intoField: "", ref: field.ref, submit: false,
                                    in: webView, announced: announced && index == 0, refreshControls: false)
            }
            if ["Typed", "Selected", "Set checked", "Checked state already"].contains(where: result.hasPrefix) {
                completed.append(field)
            } else {
                details.append("[\(field.ref)] not filled: \(result)")
            }
        }
        await PageSettle.afterInteraction(webView)
        var retained: [Int] = []
        for field in completed {
            let state = await valueState(ref: field.ref, documentID: documentID, in: webView)
            if state == "matched" {
                retained.append(field.ref)
            } else {
                details.append("[\(field.ref)] not verified: the value changed or the control is no longer available.")
            }
        }
        if !retained.isEmpty {
            details.insert("Verified refs: " + retained.map { "[\($0)]" }.joined(separator: ", ") + ".", at: 0)
        }
        return "Filled \(retained.count) of \(fields.count) fields. " + details.joined(separator: "\n") + "\n" +
            (await PageAutomationGuard.withCurrentDocument(in: webView) { await snapshot(webView) })
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
        return (try? await webView.evaluateJavaScript(script, in: selectedFrame?.frame, contentWorld: PageAutomationGuard.world)) as? String
    }

}
