// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func visualAction(name: String, action: OpenAIJSON) async -> String {
        setComputerScreenshot(nil)
        return await pageOperation(name: name) { view in
            do {
                guard let frame = computerObservation else { throw PageComputerFailure.stale }
                if action["type"] == "type", (action["text"].string?.utf8.count ?? .max) > 100_000 {
                    throw PageComputerFailure.unavailable
                }
                try await PageDriver.validateComputerAction(action, frame: frame, in: view)
                try await PageDriver.computerAction(action, frame: frame, in: view)
                _ = await PageDriver.settleAndSnippet(view)
                let scope = PageAutomationGuard.current.map {
                    PageAutomationGuard(documentURL: view.url?.absoluteString ?? $0.documentURL,
                                        snapshot: nil, validate: $0.validate)
                }
                if let (nextFrame, data) = try? await PageAutomationGuard.$current.withValue(scope, operation: {
                    try await PageDriver.computerFrame(in: view)
                }) {
                    computerObservation = nextFrame
                    setComputerScreenshot(data)
                    return action["type"] == "drag_events"
                        ? "CONTROL: Drag events dispatched. Inspect the updated screenshot and verify the result; some sites ignore synthetic events."
                        : "CONTROL: Browser action completed. Updated screenshot captured."
                }
                computerObservation = nil
                return action["type"] == "drag_events"
                    ? "CONTROL: Drag events dispatched. Screenshot unavailable; read the page to verify the result."
                    : "CONTROL: Browser action completed. Screenshot unavailable; read the page or capture it again before another visual action."
            } catch {
                if (error as? PageComputerFailure) == .unverified {
                    let scope = PageAutomationGuard.current.map {
                        PageAutomationGuard(documentURL: view.url?.absoluteString ?? $0.documentURL,
                                            snapshot: nil, validate: $0.validate)
                    }
                    if let (nextFrame, data) = try? await PageAutomationGuard.$current.withValue(scope, operation: {
                        try await PageDriver.computerFrame(in: view)
                    }) {
                        computerObservation = nextFrame
                        setComputerScreenshot(data)
                        return "Input was sent, but the page did not confirm the event. Check the updated screenshot before another action."
                    }
                    computerObservation = nil
                    setComputerScreenshot(nil)
                    return "Input was sent, but the page did not confirm the event. Read the page before another action."
                }
                computerObservation = nil
                setComputerScreenshot(nil)
                switch error as? PageComputerFailure {
                case .some(.stale):
                    return "Browser action stopped because the screenshot is out of date. Capture a new screenshot before continuing."
                case .some(.unavailable):
                    return "Browser action stopped because the page could not receive input. Keep the tab visible and try again."
                case .some(.unverified):
                    return "Input was sent, but the page did not confirm the event. Read the page before another action."
                case .some(.sensitive):
                    return "Browser action stopped at a sensitive field. Enter this information yourself."
                case .some(.declined):
                    return "Browser action was declined."
                case .some(.unsupportedKey):
                    return "Browser action stopped because that key is unsupported."
                case nil:
                    return "Browser action was interrupted. Capture a new screenshot before continuing."
                }
            }
        }
    }
}
