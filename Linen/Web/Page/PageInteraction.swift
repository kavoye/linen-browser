// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import WebKit

extension PageDriver {
    static func inspectControl(ref: Int, offset: Int = 0, in view: WKWebView) async -> String {
        guard await validateObservation(in: view, ref: ref) else { return staleMessage }
        let start = max(0, offset)
        let script = scripted(
            """
            const el = window.__linenRefs[\(ref) - 1];
            const rect = el.getBoundingClientRect();
            const result = { ref: \(ref), kind: R.kindOf(el), label: R.labelOf(el, R.kindOf(el)),
              disabled: R.disabled(el), readOnly: !!el.readOnly,
              role: el.getAttribute('role'), expanded: el.getAttribute('aria-expanded'),
              checked: el.checked ?? el.getAttribute('aria-checked'),
              bounds: { x: rect.x, y: rect.y, width: rect.width, height: rect.height } };
            if (R.isSensitiveField(el)) result.value = '(hidden)';
            else if (el.options) {
              result.options = Array.from(el.options).slice(\(start), \(start + 12)).map(o => ({
                label: R.norm(o.text).slice(0, 100), value: o.value.slice(0, 100),
                disabled: o.disabled || !!o.closest('optgroup[disabled]'), selected: o.selected }));
              result.totalOptions = el.options.length;
              const cost = value => new TextEncoder().encode(JSON.stringify(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')).length;
              while (result.options.length > 1 && cost(result) > \(max(500, outputBudget.totalCharacters - 400))) result.options.pop();
              if (\(start) + result.options.length < el.options.length) result.nextOffset = \(start) + result.options.length;
            }
            return JSON.stringify(result);
            """)
        guard let result = await evaluateJSON(script, in: view),
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        else { return staleMessage }
        return "CONTROL:\n" + String(decoding: data, as: UTF8.self)
            + "\nobservationID: " + (observation(in: view)?.id ?? "")
    }

    static func setChecked(ref: Int, checked: Bool, in view: WKWebView, announced: Bool = false) async -> String {
        guard await validateObservation(in: view, ref: ref) else { return staleMessage }
        let state = await evaluateJSON(
            scripted(
                """
                const el = window.__linenRefs[\(ref) - 1];
                return JSON.stringify({ kind: R.kindOf(el), checked: el.checked ?? (el.getAttribute('aria-checked') === 'true') });
                """), in: view)
        guard let kind = state?["kind"] as? String, ["checkbox", "radio"].contains(kind) else { return "Use a checkbox, switch, or radio ref." }
        if state?["checked"] as? Bool == checked { return "Checked state already matches.\n" + (await snapshot(view)) }
        if kind == "radio", !checked { return "Choose another radio option to change the selection." }
        let document = observation(in: view)?.documentID
        let output = await click(ref: ref, label: "", in: view, announced: announced)
        guard output.hasPrefix("Clicked") else { return output }
        guard observation(in: view)?.documentID == document else { return "The page changed before the checked state could be confirmed.\n" + output }
        let confirmed = await PageAutomationGuard.withCurrentDocument(in: view) {
            let actual = await evaluateJSON(
            scripted(
                """
                const el = window.__linenRefs[\(ref) - 1];
                return JSON.stringify({ matches: !!el?.isConnected && (el.checked ?? (el.getAttribute('aria-checked') === 'true')) === \(checked) });
                """), in: view)
            return actual?["matches"] as? Bool == true ? "confirmed" : "unconfirmed"
        }
        guard confirmed == "confirmed" else { return "The requested checked state was not confirmed.\n" + output }
        return "Set checked state to \(checked).\n" + output
    }

    static func waitForPage(condition: String, value: String, timeout: Int = 5, in view: WKWebView) async -> String {
        guard ["text", "textAbsent", "url", "ready"].contains(condition),
            condition == "ready" || !value.isEmpty,
            let encoded = jsonString(value)
        else { return "Use text, textAbsent, url, or ready with a nonempty value where required." }
        let expression: String
        switch condition {
        case "ready":
            expression = "document.readyState === 'complete'"
        case "url":
            expression = "location.href.includes(value)"
        case "textAbsent":
            expression = "!R.pageText().includes(value)"
        default:
            expression = "R.pageText().includes(value)"
        }
        let deadline = ContinuousClock.now + .seconds(min(15, max(1, timeout)))
        repeat {
            guard PageAutomationGuard.allowsExecution else { return staleMessage }
            let output = await PageAutomationGuard.withCurrentDocument(in: view) {
                let script = scripted(
                    """
                    const value = \(encoded);
                    const matches = \(expression);
                    return JSON.stringify({ matches });
                    """)
                guard let result = await evaluateJSON(script, in: view) else { return staleMessage }
                return result["matches"] as? Bool == true ? "matched" : "pending"
            }
            if output == "matched" {
                return "Condition met.\n" + (await PageAutomationGuard.withCurrentDocument(in: view) { await snapshot(view, lookingFor: value) })
            }
            if output != "pending" { return output }
            try? await Task.sleep(for: .milliseconds(150))
        } while ContinuousClock.now < deadline
        return "Timed out waiting for \(condition).\n" + (await PageAutomationGuard.withCurrentDocument(in: view) { await snapshot(view, lookingFor: value) })
    }

    static func screenshot(in view: WKWebView) async -> Data? {
        guard PageAutomationGuard.allowsExecution else { return nil }
        let document = view.url
        let safetyCheck = scripted(
            """
            return JSON.stringify({ document: R.documentID, safe: !Array.from(R.walk(document.body)).some(el =>
              R.isSensitiveField(el) && (el.value || el.isContentEditable && el.textContent)) });
            """)
        let safe = await evaluateJSON(safetyCheck, in: view)
        guard safe?["safe"] as? Bool == true else { return nil }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: min(1280, max(1, view.bounds.width)))
        guard let image = try? await view.takeSnapshot(configuration: config), PageAutomationGuard.allowsExecution, view.url == document,
            let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        let after = await evaluateJSON(safetyCheck, in: view)
        guard after?["safe"] as? Bool == true, after?["document"] as? String == safe?["document"] as? String else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
