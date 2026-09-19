// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func computerCall(_ call: OpenAIComputerCall) async throws -> String {
        setComputerScreenshot(nil)
        computerActionDeclined = false
        var metadata: OpenAIJSON = ["success": false, "safety_approved": false, "failure": "unavailable_or_denied"]
        let observing = call.actions.allSatisfy { ["screenshot", "wait"].contains($0["type"].string ?? "") }
        _ = await pageOperation(name: OpenAIComputerCall.toolName, readOnly: observing) { view in
            do {
                if !observing {
                    guard let frame = computerObservation else { throw PageComputerFailure.stale }
                    try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: true)
                }
                if !call.safetyChecks.isEmpty {
                    let details = call.safetyChecks.map { $0["message"].string ?? $0["code"].string ?? "OpenAI requested confirmation." }.joined(separator: "\n")
                    let approve = String(localized: "Approve This Action")
                    let question = String(localized: "OpenAI paused this browser action for confirmation:") + "\n\n" + details
                    let answer = await askUser([(question: question, options: [String(localized: "Decline"), approve])])
                    guard answer == approve else { throw PageComputerFailure.declined }
                    metadata["safety_approved"] = true
                }
                if let frame = computerObservation, !observing {
                    try await PageDriver.validateComputerFrame(frame, in: view, checkRevision: !observing)
                }
                for action in call.actions {
                    try Task.checkCancellation()
                    if action["type"] == "screenshot" { continue }
                    if action["type"] == "wait", observing {
                        try await Task.sleep(for: .seconds(1))
                    } else {
                        guard let frame = computerObservation else { throw PageComputerFailure.stale }
                        try await PageDriver.computerAction(action, frame: frame, in: view)
                    }
                }
                _ = await PageDriver.settleAndSnippet(view)
                let scope = PageAutomationGuard.current.map {
                    PageAutomationGuard(documentURL: view.url?.absoluteString ?? $0.documentURL,
                                        snapshot: nil, validate: $0.validate)
                }
                let (frame, data) = try await PageAutomationGuard.$current.withValue(scope) {
                    try await PageDriver.computerFrame(in: view)
                }
                computerObservation = frame
                setComputerScreenshot(data)
                metadata["success"] = true
                metadata["actions_completed"] = .integer(Int64(call.actions.count))
                return "Screenshot captured. Computer actions completed."
            } catch {
                computerObservation = nil
                setComputerScreenshot(nil)
                metadata["success"] = false
                metadata["failure"] = .string((error as? PageComputerFailure)?.rawValue ?? "interrupted")
                computerActionDeclined = error as? PageComputerFailure == .declined
                return "Computer action stopped. Capture a fresh screenshot and verify the page before continuing."
            }
        }
        if lastToolFailed {
            computerObservation = nil
            setComputerScreenshot(nil)
            metadata["success"] = false
        }
        return try metadata.text()
    }
}
