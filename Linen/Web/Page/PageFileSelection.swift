// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
final class PageFileSelection {
    static let pending = NSMapTable<WKWebView, PageFileSelection>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    let origin: String
    let observationID: String
    let validate: () -> Bool
    var selectFiles: ((WKOpenPanelParameters) async -> [URL]?)?
    var requestedPanel = false
    var cancelPanel: (() -> Void)?
    private var continuation: CheckedContinuation<Int?, Never>?
    private var completed = false
    private var count: Int?

    init(origin: String, observationID: String, validate: @escaping () -> Bool) {
        self.origin = origin
        self.observationID = observationID
        self.validate = validate
    }

    func finish(_ count: Int?) {
        guard !completed else { return }
        completed = true
        self.count = count
        continuation?.resume(returning: count)
        continuation = nil
    }

    func cancel() {
        cancelPanel?()
        finish(nil)
    }

    func wait() async -> Int? {
        let timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            if !Task.isCancelled {
                cancel()
            }
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if completed {
                    continuation.resume(returning: count)
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }
}

extension PageDriver {
    static func chooseFiles(ref: Int, in view: WKWebView, selectFiles: ((WKOpenPanelParameters) async -> [URL]?)? = nil) async -> String {
        guard selectedFrame == nil, await validateObservation(in: view, ref: ref),
              let scope = PageAutomationGuard.current, let window = view.window,
              let observation = observations.object(forKey: view),
              PageFileSelection.pending.object(forKey: view) == nil else { return staleMessage }
        let eligible = await evaluateJSON(scripted("""
            const el = window.__linenRefs[\(ref) - 1];
            const error = R.actionable(el);
            return JSON.stringify({ ok: !error && el.ownerDocument === document && el.tagName === 'INPUT' && el.type === 'file' });
            """), in: view)
        guard eligible?["ok"] as? Bool == true, await prepareAction(ref: ref, in: view) == nil else {
            return "Choose a visible file input from a fresh page observation."
        }
        let source = view.url
        let selection = PageFileSelection(origin: SitePermissions.origin(for: source), observationID: observation.id) {
            scope.validate() && view.url == source && view.window === window
        }
        selection.selectFiles = selectFiles
        PageFileSelection.pending.setObject(selection, forKey: view)
        defer {
            selection.cancel()
            PageFileSelection.pending.removeObject(forKey: view)
        }
        let opened = await evaluateJSON(scripted("""
            const el = window.__linenRefs[\(ref) - 1];
            if (!R.matchesRef(\(ref)) || R.actionable(el)) return JSON.stringify({ stale: true });
            el.click(); return JSON.stringify({ ok: true });
            """), in: view)
        guard opened?["ok"] as? Bool == true else { return staleMessage }
        let presentationTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled, !selection.requestedPanel {
                selection.cancel()
            }
        }
        defer { presentationTimeout.cancel() }
        guard let count = await selection.wait(), selection.validate(), !Task.isCancelled else {
            return "File selection cancelled or the page changed. No upload result was verified."
        }
        return "CONTROL: The user selected \(count) files. Check the page for upload completion.\n" + (await settleAndSnippet(view))
    }
}
