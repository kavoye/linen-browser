// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Carbon.HIToolbox
import Foundation
import WebKit

@MainActor
final class PageComputerFrame {
    weak var view: WKWebView?
    let geometry: CGSize
    let zoom: CGFloat
    let pixels: CGSize
    let document: String
    let revision: Int
    let screenshot: Data
    init(view: WKWebView, pixels: CGSize, document: String, revision: Int, screenshot: Data) {
        self.view = view
        self.geometry = view.bounds.size
        self.zoom = view.pageZoom
        self.pixels = pixels
        self.document = document
        self.revision = revision
        self.screenshot = screenshot
    }
}

nonisolated enum PageComputerFailure: String, Error {
    case stale, unavailable, unverified, sensitive, declined, unsupportedKey
}

@MainActor
private final class AssistantPointerView: NSView {
    var hideTask: Task<Void, Never>?

    override var isFlipped: Bool {
        true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath()
        shape.move(to: NSPoint(x: 2, y: 2))
        shape.line(to: NSPoint(x: 2, y: 20))
        shape.line(to: NSPoint(x: 6, y: 16))
        shape.line(to: NSPoint(x: 9, y: 23))
        shape.line(to: NSPoint(x: 13, y: 21))
        shape.line(to: NSPoint(x: 10, y: 14))
        shape.line(to: NSPoint(x: 17, y: 14))
        shape.close()
        NSColor.controlAccentColor.setFill()
        shape.fill()
        NSColor.white.setStroke()
        shape.lineWidth = 2
        shape.stroke()
    }
}

extension PageDriver {
    private static let computerContext = """
        if (!window.__linenComputer) {
          const state = { revision: 0 };
          window.__linenComputer = state;
          const observer = new MutationObserver(() => state.revision++);
          observer.observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
          window.addEventListener('scroll', () => state.revision++, true);
          window.addEventListener('resize', () => state.revision++);
        }
        """

    static func computerFrame(in view: WKWebView) async throws -> (PageComputerFrame, Data) {
        guard view.bounds.width > 0, view.bounds.height > 0, !view.isLoading else { throw PageComputerFailure.unavailable }
        let deadline = ContinuousClock.now + .seconds(1)
        repeat {
            let before = await evaluateJSON(scripted(computerContext + "return JSON.stringify({ document: R.documentID, revision: window.__linenComputer.revision });"), in: view)
            guard let data = await screenshot(in: view), let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
                  let document = before?["document"] as? String, let revision = before?["revision"] as? Int else { throw PageComputerFailure.unavailable }
            let after = await evaluateJSON(scripted("return JSON.stringify({ document: R.documentID, revision: window.__linenComputer?.revision });"), in: view)
            guard after?["document"] as? String == document else { throw PageComputerFailure.stale }
            if after?["revision"] as? Int == revision {
                return (PageComputerFrame(view: view, pixels: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh), document: document, revision: revision, screenshot: data), data)
            }
            await Task.yield()
        } while ContinuousClock.now < deadline
        throw PageComputerFailure.stale
    }

    static func validateComputerFrame(_ frame: PageComputerFrame, in view: WKWebView, checkRevision: Bool) async throws {
        guard frame.view === view, frame.geometry == view.bounds.size, frame.zoom == view.pageZoom,
              !view.isLoading, PageAutomationGuard.allowsExecution else {
            throw PageComputerFailure.stale
        }
        let state = await evaluateJSON(scripted("return JSON.stringify({ document: R.documentID, revision: window.__linenComputer?.revision });"), in: view)
        guard state?["document"] as? String == frame.document,
              !checkRevision || state?["revision"] as? Int == frame.revision else { throw PageComputerFailure.stale }
    }

    static func validateComputerAction(_ action: OpenAIJSON, frame: PageComputerFrame, in view: WKWebView) async throws {
        try await validateComputerFrame(frame, in: view, checkRevision: false)
        let state = await evaluateJSON(scripted("return JSON.stringify({ revision: window.__linenComputer?.revision });"), in: view)
        guard let revision = state?["revision"] as? Int else { throw PageComputerFailure.stale }
        guard revision != frame.revision else { return }

        // Changes elsewhere on the page, such as a carousel, do not invalidate an unchanged target.
        guard ["click", "double_click", "move", "drag", "drag_events"].contains(action["type"].string ?? ""),
              let point = try? computerPoint(action["x"] == .null ? (action["path"].array?.first ?? .null) : action, frame: frame),
              let (fresh, _) = try? await computerFrame(in: view),
              screenshotMatches(frame, fresh, around: point)
        else { throw PageComputerFailure.stale }
    }

    private static func screenshotMatches(_ before: PageComputerFrame, _ after: PageComputerFrame, around point: CGPoint) -> Bool {
        guard before.geometry == after.geometry, before.zoom == after.zoom, before.pixels == after.pixels,
              let first = NSBitmapImageRep(data: before.screenshot), let second = NSBitmapImageRep(data: after.screenshot)
        else { return false }
        let x = Int(point.x * before.pixels.width / before.geometry.width)
        let y = Int(point.y * before.pixels.height / before.geometry.height)
        let radius = 24
        var sampled = 0
        var changed = 0
        for row in stride(from: max(0, y - radius), through: min(first.pixelsHigh - 1, y + radius), by: 4) {
            for column in stride(from: max(0, x - radius), through: min(first.pixelsWide - 1, x + radius), by: 4) {
                guard let a = first.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                      let b = second.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                sampled += 1
                if abs(a.redComponent - b.redComponent) > 0.08 ||
                    abs(a.greenComponent - b.greenComponent) > 0.08 ||
                    abs(a.blueComponent - b.blueComponent) > 0.08 {
                    changed += 1
                }
            }
        }
        return sampled > 0 && changed * 100 <= sampled
    }

    private static func computerPoint(_ action: OpenAIJSON, frame: PageComputerFrame) throws -> CGPoint {
        guard let x = action["x"].finiteNumber, let y = action["y"].finiteNumber, x >= 0, y >= 0,
              CGFloat(x) < frame.pixels.width, CGFloat(y) < frame.pixels.height else { throw PageComputerFailure.stale }
        return CGPoint(x: CGFloat(x) * frame.geometry.width / frame.pixels.width, y: CGFloat(y) * frame.geometry.height / frame.pixels.height)
    }

    private static func computerTarget(point: CGPoint?, in view: WKWebView) async throws -> [String: Any] {
        let x = point.map { String(Double($0.x / view.pageZoom)) } ?? "null"
        let y = point.map { String(Double($0.y / view.pageZoom)) } ?? "null"
        let body = """
            let doc = document, root = doc, x = \(x), y = \(y), el = x === null ? doc.activeElement : root.elementFromPoint(x, y);
            for (let depth = 0; depth < 30 && el; depth++) {
              if (el.tagName === 'IFRAME' || el.tagName === 'FRAME') {
                let child; try { child = el.contentDocument; } catch (_) {}
                if (!child?.body) return JSON.stringify({ blocked: true });
                const rect = el.getBoundingClientRect();
                if (x !== null) {
                    x -= rect.left + el.clientLeft; y -= rect.top + el.clientTop;
                }
                doc = child; root = child; el = x === null ? doc.activeElement : root.elementFromPoint(x, y); continue;
              }
              if (el.shadowRoot) {
                const next = x === null ? el.shadowRoot.activeElement : el.shadowRoot.elementFromPoint(x, y);
                if (next && next !== el) {
                    root = el.shadowRoot; el = next; continue;
                }
              }
              break;
            }
            if (!el?.isConnected) return JSON.stringify({ blocked: true });
            el = el.closest('input,textarea,button,a,select,[contenteditable=true],[role=button],[role=textbox]') || el;
            if (R.isSensitiveField(el) || R.disabled(el) || el.tagName === 'INPUT' && el.type === 'file') return JSON.stringify({ sensitive: true });
            window.__linenComputerTarget = el;
            const label = R.labelOf(el, R.kindOf(el));
            const context = (el.form?.innerText || el.closest('form,[role=dialog]')?.innerText || '').slice(0, 1200);
            const rect = el.getBoundingClientRect();
            return JSON.stringify({ label, context, signature: JSON.stringify([R.documentID, el.tagName, el.id, el.type, el.href, label, context, rect.x, rect.y, rect.width, rect.height]),
              editable: el.isContentEditable || ['INPUT','TEXTAREA'].includes(el.tagName) });
            """
        guard let result = await evaluateJSON(scripted(body), in: view), result["blocked"] as? Bool != true else { throw PageComputerFailure.unavailable }
        guard result["sensitive"] as? Bool != true else { throw PageComputerFailure.sensitive }
        return result
    }

    static func computerAction(_ action: OpenAIJSON, frame: PageComputerFrame, in view: WKWebView) async throws {
        try await validateComputerFrame(frame, in: view, checkRevision: false)
        guard let type = action["type"].string else { throw PageComputerFailure.unavailable }
        if type == "screenshot" {
            return
        }
        if type == "wait" {
            try await Task.sleep(for: .seconds(1))
            return
        }
        let point: CGPoint?
        if action["x"] != .null {
            point = try computerPoint(action, frame: frame)
        } else if let first = action["path"].array?.first {
            point = try computerPoint(first, frame: frame)
        } else { point = nil }
        let target = try await computerTarget(point: point, in: view)
        let activates = ["click", "double_click", "drag", "drag_events"].contains(type)
            && !["back", "forward"].contains(action["button"].string ?? "")
        let submitsKey = type == "keypress" && (action["keys"].array ?? []).contains {
            ["ENTER", "RETURN", "SPACE", " "].contains($0.string?.uppercased() ?? "")
        }
        if activates || submitsKey,
           let category = SensitiveAction.category(of: target["label"] as? String ?? "", context: target["context"] as? String ?? "") {
            guard await AgentActionConsent.permit(label: target["label"] as? String ?? "Browser action", category: category,
                                                  host: view.url?.host(), authoredByAI: AgentAuthoredText.isPresent(in: view)) else { throw PageComputerFailure.declined }
        }
        try await validateComputerFrame(frame, in: view, checkRevision: false)
        let current = try await computerTarget(point: point, in: view)
        guard current["signature"] as? String == target["signature"] as? String else { throw PageComputerFailure.stale }
        guard let window = view.window, window.attachedSheet == nil else { throw PageComputerFailure.unavailable }
        if type == "move", !NSApp.isActive || !window.isKeyWindow { throw PageComputerFailure.unavailable }
        guard window.makeFirstResponder(view) else { throw PageComputerFailure.unavailable }
        let acceptedMoves = window.acceptsMouseMovedEvents
        if type == "move" { window.acceptsMouseMovedEvents = true }
        defer { window.acceptsMouseMovedEvents = acceptedMoves }
        let modifiers = computerModifiers(action["keys"].array?.compactMap(\.string) ?? [])
        let event = computerReceiptEvent(action)
        if let event {
            try await installComputerReceipt(event, in: view)
        }
        let documentURL = view.url
        do {
            try await performComputerAction(action, frame: frame, point: point, current: current, modifiers: modifiers, in: view, window: window)
            if event != nil {
                try await awaitComputerReceipt(in: view, documentURL: documentURL)
            }
        } catch {
            _ = await evaluateJSON(scripted("window.__linenComputerAck?.dispose(); return JSON.stringify({ ok: true });"), in: view)
            throw error
        }
    }

    private static func computerReceiptEvent(_ action: OpenAIJSON) -> String? {
        switch action["type"].string {
        case "click":
            return ["left": "click", "right": "contextmenu", "wheel": "mouseup"][action["button"].string ?? "left"]
        case "double_click":
            return "dblclick"
        case "drag":
            return "mouseup"
        case "move":
            return "mousemove"
        case "keypress":
            return "keyup"
        case "type":
            return action["text"] == "" ? nil : "input"
        default:
            return nil
        }
    }

    private static func installComputerReceipt(_ event: String, in view: WKWebView) async throws {
        let encoded = try OpenAIJSON.string(event).text()
        let result = await evaluateJSON(scripted("""
            window.__linenComputerAck?.dispose();
            const type = \(encoded), docs = new Set([document, ...Array.from(R.walk(document.body)).map(el => el.ownerDocument)]);
            const state = { received: false };
            const handler = event => { if (event.isTrusted) state.received = true; };
            const keyHandler = event => { if (event.isTrusted) state.keyDown = event; };
            for (const doc of docs) {
              doc.addEventListener(type, handler, true);
              if (type === 'keyup') doc.addEventListener('keydown', keyHandler, true);
            }
            state.dispose = () => {
              for (const doc of docs) { doc.removeEventListener(type, handler, true); doc.removeEventListener('keydown', keyHandler, true); }
              state.keyDown = null;
            };
            window.__linenComputerAck = state;
            return JSON.stringify({ ok: true });
            """), in: view)
        guard result?["ok"] as? Bool == true else { throw PageComputerFailure.unavailable }
    }

    private static func awaitComputerReceipt(in view: WKWebView, documentURL: URL?) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        repeat {
            try Task.checkCancellation()
            guard PageAutomationGuard.allowsExecution else { throw PageComputerFailure.stale }
            if view.isLoading || view.url != documentURL {
                return
            }
            let result = await evaluateJSON(scripted("""
                const state = window.__linenComputerAck;
                if (state?.received) state.dispose();
                return JSON.stringify({ received: !!state?.received });
                """), in: view)
            if result?["received"] as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw PageComputerFailure.unverified
    }

    private static func performComputerAction(_ action: OpenAIJSON, frame: PageComputerFrame, point: CGPoint?, current: [String: Any],
                                              modifiers: NSEvent.ModifierFlags, in view: WKWebView, window: NSWindow) async throws {
        guard window.attachedSheet == nil else { throw PageComputerFailure.unavailable }
        let type = action["type"].string ?? ""
        if let point, ["click", "double_click", "move", "drag", "drag_events"].contains(type) {
            await showAssistantPointer(at: point, in: view)
            try await validateComputerAction(action, frame: frame, in: view)
            let target = try await computerTarget(point: point, in: view)
            guard target["signature"] as? String == current["signature"] as? String else {
                throw PageComputerFailure.stale
            }
        }
        switch type {
        case "click", "double_click":
            guard let point else { throw PageComputerFailure.unavailable }
            try await performComputerClick(action, type: type, point: point, modifiers: modifiers, in: view, window: window)
        case "move":
            guard let point else { throw PageComputerFailure.unavailable }
            try computerMouse(point: point, button: "left", phase: "move", modifiers: modifiers, in: view, window: window)
        case "drag_events":
            let path = try (action["path"].array ?? []).map { try computerPoint($0, frame: frame) }
            guard (2...50).contains(path.count), let end = path.last else { throw PageComputerFailure.unavailable }
            let destination = try await computerTarget(point: end, in: view)
            if let category = SensitiveAction.category(of: destination["label"] as? String ?? "", context: destination["context"] as? String ?? "") {
                guard await AgentActionConsent.permit(label: destination["label"] as? String ?? "Drop target", category: category,
                    host: view.url?.host(), authoredByAI: AgentAuthoredText.isPresent(in: view)) else { throw PageComputerFailure.declined }
            }
            try await validateComputerFrame(frame, in: view, checkRevision: true)
            try await dispatchDrag(path: path, modifiers: modifiers, in: view)
        case "drag":
            let path = try (action["path"].array ?? []).map { try computerPoint($0, frame: frame) }
            guard let start = path.first, let end = path.last else { throw PageComputerFailure.unavailable }
            _ = try await computerTarget(point: end, in: view)
            try await validateComputerFrame(frame, in: view, checkRevision: false)
            try computerMouse(point: start, button: "left", phase: "down", modifiers: modifiers, in: view, window: window)
            for point in path.dropFirst() {
                try computerMouse(point: point, button: "left", phase: "drag", modifiers: modifiers, in: view, window: window)
            }
            try computerMouse(point: end, button: "left", phase: "up", modifiers: modifiers, in: view, window: window)
        case "scroll":
            let x = action["scroll_x"].finiteNumber ?? 0, y = action["scroll_y"].finiteNumber ?? 0
            let result = await evaluateJSON(scripted("""
                let el = window.__linenComputerTarget;
                while (el && el !== el.ownerDocument.scrollingElement) {
                  const style = el.ownerDocument.defaultView.getComputedStyle(el);
                  if ((\(y) && el.scrollHeight > el.clientHeight && /auto|scroll/.test(style.overflowY)) ||
                      (\(x) && el.scrollWidth > el.clientWidth && /auto|scroll/.test(style.overflowX))) break;
                  el = el.parentElement || el.getRootNode().host || el.ownerDocument.scrollingElement;
                }
                if (!el) return JSON.stringify({ ok: false });
                el.scrollBy({ left: \(x), top: \(y), behavior: 'instant' });
                return JSON.stringify({ ok: true });
                """), in: view)
            guard result?["ok"] as? Bool == true else { throw PageComputerFailure.unavailable }
        case "type":
            guard current["editable"] as? Bool == true, window.makeFirstResponder(view), let text = action["text"].string else {
                throw PageComputerFailure.unavailable
            }
            view.insertText(text)
            AgentAuthoredText.record(in: view)
        case "keypress":
            try await computerKey(action["keys"].array?.compactMap(\.string) ?? [], frame: frame, in: view, window: window)
        default:
            throw PageComputerFailure.unavailable
        }
        try Task.checkCancellation()
    }

    private static func performComputerClick(
        _ action: OpenAIJSON, type: String, point: CGPoint, modifiers: NSEvent.ModifierFlags,
        in view: WKWebView, window: NSWindow
    ) async throws {
        let button = action["button"].string ?? "left"
        if button == "back" {
            view.goBack(); return
        }
        if button == "forward" {
            view.goForward(); return
        }
        if button == "right" {
            _ = await evaluateJSON(scripted("document.addEventListener('contextmenu', e => e.preventDefault(), { once: true, capture: true }); return JSON.stringify({ ok: true });"), in: view)
        }
        for count in 1...(type == "double_click" ? 2 : 1) {
            try computerMouse(point: point, button: button, phase: "down", count: count, modifiers: modifiers, in: view, window: window)
            try computerMouse(point: point, button: button, phase: "up", count: count, modifiers: modifiers, in: view, window: window)
        }
    }

    private static func showAssistantPointer(at point: CGPoint, in view: WKWebView) async {
        let pointer = view.subviews.compactMap { $0 as? AssistantPointerView }.first ?? AssistantPointerView(frame: .zero)
        pointer.identifier = NSUserInterfaceItemIdentifier("assistant-pointer")
        let localY = view.isFlipped ? point.y : view.bounds.height - point.y
        let destination = NSPoint(x: point.x - 2, y: localY - 2)
        pointer.hideTask?.cancel()
        if pointer.superview == nil {
            pointer.frame = NSRect(origin: destination, size: NSSize(width: 24, height: 26))
            view.addSubview(pointer)
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                pointer.animator().setFrameOrigin(destination)
            }
        }
        pointer.hideTask = Task { [weak pointer] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            pointer?.removeFromSuperview()
        }
    }

    private static func computerMouse(point: CGPoint, button: String, phase: String, count: Int = 1, modifiers: NSEvent.ModifierFlags = [], in view: WKWebView, window: NSWindow) throws {
        guard PageAutomationGuard.allowsExecution, view.window === window else { throw PageComputerFailure.stale }
        let local = CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
        let type: NSEvent.EventType
        switch (button, phase) {
        case (_, "move"):
            type = .mouseMoved
        case (_, "drag"):
            type = .leftMouseDragged
        case ("right", "down"):
            type = .rightMouseDown
        case ("right", _):
            type = .rightMouseUp
        case ("wheel", "down"):
            type = .otherMouseDown
        case ("wheel", _):
            type = .otherMouseUp
        case (_, "down"):
            type = .leftMouseDown
        default:
            type = .leftMouseUp
        }
        guard let event = NSEvent.mouseEvent(with: type, location: view.convert(local, to: nil), modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: phase == "move" ? 0 : count, pressure: phase == "up" || phase == "move" ? 0 : 1) else {
            throw PageComputerFailure.unavailable
        }
        guard let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
              hit.isDescendant(of: view), window.attachedSheet == nil else { throw PageComputerFailure.unavailable }
        if phase == "move" {
            let selector = #selector(NSResponder.mouseMoved(with:))
            guard let owner = view.trackingAreas.first(where: {
                $0.options.contains([.mouseMoved, .mouseEnteredAndExited])
                    && ($0.options.contains(.inVisibleRect) || $0.rect.contains(local))
                    && ($0.owner as? NSObject) !== view
                    && ($0.owner as? NSObject)?.responds(to: selector) == true
            })?.owner as? NSObject else { throw PageComputerFailure.unavailable }
            owner.perform(selector, with: event)
        } else {
            window.sendEvent(event)
        }
    }

    private static func computerModifiers(_ keys: [String]) -> NSEvent.ModifierFlags {
        let normalized = keys.map { $0.uppercased() }
        var flags: NSEvent.ModifierFlags = []
        if normalized.contains("SHIFT") {
            flags.insert(.shift)
        }
        if normalized.contains("ALT") || normalized.contains("OPTION") {
            flags.insert(.option)
        }
        if normalized.contains("CTRL") || normalized.contains("CONTROL") {
            flags.insert(.control)
        }
        if normalized.contains("META") || normalized.contains("CMD") || normalized.contains("COMMAND") {
            flags.insert(.command)
        }
        return flags
    }

    private static func computerKey(_ keys: [String], frame: PageComputerFrame, in view: WKWebView, window: NSWindow) async throws {
        guard keys.allSatisfy({ $0.utf8.allSatisfy { $0 < 128 } }) else { throw PageComputerFailure.unsupportedKey }
        let normalized = keys.map { $0.uppercased() }
        var flags = computerModifiers(keys)
        let modifiers: Set<String> = ["SHIFT", "ALT", "OPTION", "CTRL", "CONTROL", "META", "CMD", "COMMAND"]
        let ordinary = normalized.filter { !modifiers.contains($0) }
        guard ordinary.count == 1, let key = ordinary.first,
              flags.isDisjoint(with: [.command, .control]) || (key == "A" && flags.isDisjoint(with: [.shift, .option]))
        else { throw PageComputerFailure.unsupportedKey }
        let named: [String: (UInt16, String)] = [
            "ENTER": (36, "\r"), "RETURN": (36, "\r"), "TAB": (48, "\t"), "ESC": (53, "\u{1b}"), "ESCAPE": (53, "\u{1b}"),
            "SPACE": (49, " "), "ARROWLEFT": (123, "\u{f702}"), "ARROWRIGHT": (124, "\u{f703}"),
            "ARROWDOWN": (125, "\u{f701}"), "ARROWUP": (126, "\u{f700}"), "HOME": (115, "\u{f729}"), "END": (119, "\u{f72b}"),
            "BACKSPACE": (51, "\u{7f}"), "DELETE": (117, "\u{f728}"), "PAGEDOWN": (121, "\u{f72d}"), "PAGEUP": (116, "\u{f72c}"),
        ]
        let aliases = ["UP": "ARROWUP", "DOWN": "ARROWDOWN", "LEFT": "ARROWLEFT", "RIGHT": "ARROWRIGHT"]
        var entry = named[aliases[key] ?? key]
        if let code = computerLetterCodes[key] {
            entry = (UInt16(code), flags.contains(.shift) ? key : key.lowercased())
        } else if let printable = computerPrintableKeys[key] {
            entry = (UInt16(printable.code), flags.contains(.shift) ? printable.shifted : key)
        } else if let shifted = computerPrintableKeys.first(where: { $0.value.shifted == key }) {
            flags.insert(.shift)
            entry = (UInt16(shifted.value.code), key)
        }
        guard let (code, characters) = entry else { throw PageComputerFailure.unsupportedKey }
        if key == "A", flags.contains(.control) {
            flags.remove(.control); flags.insert(.command)
        }
        guard window.attachedSheet == nil, window.makeFirstResponder(view) else { throw PageComputerFailure.unavailable }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard PageAutomationGuard.allowsExecution,
                  let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            else { throw PageComputerFailure.stale }
            if type == .keyDown {
                view.keyDown(with: event)
                if flags.contains(.command) {
                    try await computerSelectAll(frame: frame, in: view, window: window)
                }
            } else {
                view.keyUp(with: event)
            }
        }
    }

    private static func computerSelectAll(frame: PageComputerFrame, in view: WKWebView, window: NSWindow) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        repeat {
            try Task.checkCancellation()
            try await validateComputerFrame(frame, in: view, checkRevision: false)
            let result = await evaluateJSON(scripted("""
                const e = window.__linenComputerAck?.keyDown;
                return JSON.stringify({ received: !!e && e.key === 'a' && e.code === 'KeyA'
                  && e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey, prevented: !!e?.defaultPrevented });
                """), in: view)
            if result?["received"] as? Bool == true {
                if result?["prevented"] as? Bool != true {
                    _ = try await computerTarget(point: nil, in: view)
                    try await validateComputerFrame(frame, in: view, checkRevision: false)
                    guard window.attachedSheet == nil, view.window === window, window.firstResponder === view else { throw PageComputerFailure.unavailable }
                    view.selectAll(nil)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw PageComputerFailure.unavailable
    }

    private static let computerLetterCodes: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
    ]

    private static let computerPrintableKeys: [String: (code: Int, shifted: String)] = [
        "0": (kVK_ANSI_0, ")"), "1": (kVK_ANSI_1, "!"), "2": (kVK_ANSI_2, "@"), "3": (kVK_ANSI_3, "#"), "4": (kVK_ANSI_4, "$"),
        "5": (kVK_ANSI_5, "%"), "6": (kVK_ANSI_6, "^"), "7": (kVK_ANSI_7, "&"), "8": (kVK_ANSI_8, "*"), "9": (kVK_ANSI_9, "("),
        "-": (kVK_ANSI_Minus, "_"), "=": (kVK_ANSI_Equal, "+"), "[": (kVK_ANSI_LeftBracket, "{"), "]": (kVK_ANSI_RightBracket, "}"),
        "\\": (kVK_ANSI_Backslash, "|"), ";": (kVK_ANSI_Semicolon, ":"), "'": (kVK_ANSI_Quote, "\""),
        ",": (kVK_ANSI_Comma, "<"), ".": (kVK_ANSI_Period, ">"), "/": (kVK_ANSI_Slash, "?"), "`": (kVK_ANSI_Grave, "~"),
        " ": (kVK_Space, " "),
    ]
}
