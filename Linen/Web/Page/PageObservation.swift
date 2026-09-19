// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated struct PageOutputBudget: Sendable {
    var textCharacters = 2400
    var controls = 40
    var totalCharacters = 6000

    static func cost(_ text: String) -> Int {
        text.utf8.reduce(0) { count, byte in
            count + (byte == 38 ? 5 : byte == 60 || byte == 62 ? 4 : 1)
        }
    }

    static func prefix(_ text: String, fitting limit: Int) -> String {
        var used = 0
        return String(
            text.prefix { character in
                used += cost(String(character))
                return used <= max(0, limit)
            })
    }
}

@MainActor
final class PageObservation {
    let id: String
    let documentID: String
    let url: String
    let refs: Set<Int>

    init(id: String, documentID: String, url: String, refs: Set<Int>) {
        self.id = id
        self.documentID = documentID
        self.url = url
        self.refs = refs
    }
}

extension PageDriver {
    @TaskLocal static var outputBudget = PageOutputBudget()
    @TaskLocal static var expectedObservation: String?
    static let observations = NSMapTable<WKWebView, PageObservation>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    static func observation(in view: WKWebView) -> PageObservation? {
        observations.object(forKey: view)
    }

    static func validateObservation(in view: WKWebView, ref: Int) async -> Bool {
        guard let prior = observation(in: view), prior.refs.contains(ref),
            expectedObservation == nil || expectedObservation == prior.id
        else { return false }
        let value =
            try? await view.evaluateJavaScript(
                "[window.__linen?.documentID || '', window.__linenSnapshot || '', location.href, window.__linen?.matchesRef(\(ref)) ? 'valid' : 'changed']",
                in: nil, contentWorld: PageAutomationGuard.world
            ) as? [String]
        return value == [prior.documentID, prior.id, prior.url, "valid"] && PageAutomationGuard.allowsExecution
    }

    static func prepareAction(ref: Int, in view: WKWebView) async -> String? {
        let deadline = ContinuousClock.now + .seconds(1)
        var previousBounds: [Double]?
        var lastError = "The control did not become stable. Read the page again."
        repeat {
            guard await validateObservation(in: view, ref: ref) else { return staleMessage }
            let result = await evaluateJSON(
                scripted(
                    """
                    const el = window.__linenRefs[\(ref) - 1];
                    const error = R.actionable(el);
                    const r = el.getBoundingClientRect();
                    const moving = el.getAnimations().some(animation => animation.playState === 'running'
                      && animation.effect?.getKeyframes().some(frame => Object.keys(frame).some(key =>
                        /^(transform|translate|rotate|scale|width|height|left|right|top|bottom|margin|padding)/.test(key))));
                    return JSON.stringify({ error, moving, bounds: [r.x, r.y, r.width, r.height] });
                    """), in: view)
            guard let result else { return staleMessage }
            if let error = result["error"] as? String, !error.isEmpty {
                lastError = error
                previousBounds = nil
                if error.contains("disabled") { return error }
            } else if result["moving"] as? Bool == true {
                previousBounds = nil
            } else if let bounds = result["bounds"] as? [Double] {
                if let previousBounds, zip(bounds, previousBounds).allSatisfy({ abs($0 - $1) < 0.5 }) {
                    return nil
                }
                previousBounds = bounds
            }
            try? await Task.sleep(for: .milliseconds(40))
        } while ContinuousClock.now < deadline
        return lastError
    }
}
