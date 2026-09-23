// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import WebKit

extension PageDriver {
    static func hover(ref: Int, in view: WKWebView) async -> String {
        guard await validateObservation(in: view, ref: ref) else { return staleMessage }
        await announce(ref: ref, in: view, pause: false)
        guard await validateObservation(in: view, ref: ref) else { return staleMessage }
        let result = await evaluateJSON(
            scripted(
                """
                const el = window.__linenRefs[\(ref) - 1];
                const error = R.actionable(el, false);
                if (error) return JSON.stringify({ error });
                const realm = el.ownerDocument.defaultView;
                const rect = el.getBoundingClientRect();
                const options = { bubbles: true, composed: true, clientX: rect.x + rect.width / 2,
                  clientY: rect.y + rect.height / 2, pointerId: 1, pointerType: 'mouse', isPrimary: true };
                const previous = window.__linenHovered;
                if (previous && previous !== el && previous.isConnected) {
                  previous.dispatchEvent(new realm.MouseEvent('mouseout', { ...options, relatedTarget: el }));
                  previous.dispatchEvent(new realm.MouseEvent('mouseleave', { ...options, bubbles: false, relatedTarget: el }));
                }
                window.__linenHovered = el;
                for (const type of ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointermove', 'mousemove']) {
                  if (!el.isConnected) break;
                  const Event = type.startsWith('pointer') ? realm.PointerEvent : realm.MouseEvent;
                  el.dispatchEvent(new Event(type, { ...options, bubbles: !type.endsWith('enter') }));
                }
                return JSON.stringify({ ok: true });
                """), in: view)
        if let error = result?["error"] as? String { return error }
        guard result?["ok"] as? Bool == true else { return staleMessage }
        return "Dispatched hover handlers. CSS-only hover is unavailable; check the observed result.\n" + (await settleAndSnippet(view))
    }

    static func pressKey(_ key: String, ref: Int, in view: WKWebView) async -> String {
        let keys: [String: (UInt16, String)] = [
            "Enter": (36, "\r"), "Tab": (48, "\t"), "Escape": (53, "\u{1b}"), "Space": (49, " "),
            "ArrowLeft": (123, "\u{f702}"), "ArrowRight": (124, "\u{f703}"),
            "ArrowDown": (125, "\u{f701}"), "ArrowUp": (126, "\u{f700}"),
            "Home": (115, "\u{f729}"), "End": (119, "\u{f72b}"),
            "Backspace": (51, "\u{7f}"), "Delete": (117, "\u{f728}"),
        ]
        guard let (code, characters) = keys[key] else {
            return "Use Enter, Tab, Escape, Space, ArrowLeft, ArrowRight, ArrowDown, ArrowUp, Home, End, Backspace, or Delete."
        }
        guard view.window != nil else { return "Keyboard input requires a visible tab. Switch to the page first." }
        let resolved = await resolve(ref: ref, label: "", kinds: #"["field","button","link","checkbox","radio","combobox","select","scrollarea"]"#, in: view)
        guard case .success(let found) = resolved else { return staleMessage }
        if key == "Enter" || key == "Space", let category = SensitiveAction.category(of: found.label, context: found.context) {
            guard
                await AgentActionConsent.permit(
                    label: found.label, category: category, host: (selectedFrame?.url ?? view.url)?.host(),
                    authoredByAI: AgentAuthoredText.isPresent(in: view))
            else {
                return SensitiveAction.declined(found.label, category: category)
            }
        }
        guard await validateObservation(in: view, ref: ref), let window = view.window else { return staleMessage }
        let ready = await evaluateJSON(
            scripted(
                """
                const el = window.__linenRefs[\(ref) - 1];
                if (R.isSensitiveField(el)) return JSON.stringify({ error: 'The user must interact with sensitive fields.' });
                const error = R.actionable(el);
                if (error) return JSON.stringify({ error });
                el.focus();
                return JSON.stringify({ focused: el.ownerDocument.activeElement === el || el.getRootNode().activeElement === el });
                """), in: view)
        if let error = ready?["error"] as? String { return error }
        guard ready?["focused"] as? Bool == true, window.makeFirstResponder(view),
            await validateObservation(in: view, ref: ref)
        else { return "The control could not receive keyboard focus." }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard PageAutomationGuard.allowsExecution else { return staleMessage }
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            else { return "Could not create keyboard input." }
            if type == .keyDown {
                view.keyDown(with: event)
            } else {
                view.keyUp(with: event)
            }
        }
        return "Sent \(key). Check the resulting page.\n" + (await settleAndSnippet(view))
    }

}
