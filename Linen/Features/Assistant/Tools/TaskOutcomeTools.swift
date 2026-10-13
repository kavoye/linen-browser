// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import WebKit

nonisolated struct RecordTaskOutcomeTool: Tool {
    let name = "recordTaskOutcome"
    let description = """
        Before changing a website, record each requested outcome with a stable ID and its requirement. Add missing outcomes; existing requirements \
        cannot be removed or rewritten. Saved outcomes survive compaction and continuation.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var outcomeID: String
        var requirement: String
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.recordOutcome(id: arguments.outcomeID, requirement: arguments.requirement)
    }
}

nonisolated struct VerifyTaskOutcomeTool: Tool {
    let name = "verifyTaskOutcome"
    let description = """
        Verify a recorded outcome against freshly read page text. Supply specific expected text and the exact page URL. For a saved record, first \
        reopen its URL with navigate, then verify its persisted content. The browser records evidence only if the text matches. Verify after all \
        changes. Never use a button label or a draft field as proof of saving. For saved control state, \
        supply controlRef, observationID, and expectedValue or expectedChecked; expectedText may be empty. \
        Reopen the saved page first when persistence matters. Supply frameID for an embedded page.
        """
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var outcomeID: String
        var page: String?
        var frameID: String?
        var expectedURL: String
        var expectedText: String
        var controlRef: Int?
        var observationID: String?
        var expectedValue: String?
        var expectedChecked: Bool?
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.verifyOutcome(id: arguments.outcomeID, page: arguments.page, frameID: arguments.frameID,
            expectedURL: arguments.expectedURL, expectedText: arguments.expectedText, controlRef: arguments.controlRef,
            observationID: arguments.observationID, expectedValue: arguments.expectedValue, expectedChecked: arguments.expectedChecked)
    }
}

nonisolated struct BlockTaskOutcomeTool: Tool {
    let name = "blockTaskOutcome"
    let description = "Record why an outcome needs the user or cannot currently be verified. This pauses the task without claiming success."
    let toolkit: AgentToolkit
    @Generable struct Arguments {
        var outcomeID: String
        var reason: String
    }
    func call(arguments: Arguments) async throws -> String {
        await toolkit.blockOutcome(id: arguments.outcomeID, reason: arguments.reason)
    }
}

extension AgentToolkit {
    func recordOutcome(id: String, requirement: String) -> String {
        taskLedger.add(id: id, requirement: requirement)
            ? "Outcome recorded. Complete the work, then verify its result."
            : rejectTool(name: "recordTaskOutcome", reason: "Use a unique ID (1–80 bytes) and requirement (1–1,000 bytes). Existing outcomes cannot be rewritten. Maximum: 64 outcomes.")
    }

    func blockOutcome(id: String, reason: String) -> String {
        guard let index = taskLedger.outcomes.firstIndex(where: { $0.id == id }), !reason.isEmpty, reason.utf8.count <= 1_000 else {
            return rejectTool(name: "blockTaskOutcome", reason: "Provide a recorded outcome ID and a brief reason.")
        }
        taskLedger.outcomes[index].evidence = nil
        taskLedger.outcomes[index].blocker = reason
        return "Outcome blocked. Explain what is unfinished and what the user needs to do."
    }

    func verifyOutcome(id: String, page: String?, frameID: String? = nil, expectedURL: String, expectedText: String,
                       controlRef: Int? = nil, observationID: String? = nil, expectedValue: String? = nil, expectedChecked: Bool? = nil) async -> String {
        guard let index = taskLedger.outcomes.firstIndex(where: { $0.id == id }),
              controlRef != nil || expectedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3,
              expectedText.utf8.count <= 1_000, (expectedValue?.utf8.count ?? 0) <= 1_000 else {
            return rejectTool(name: "verifyTaskOutcome", reason: "Provide a recorded outcome ID and specific expected page text of 3–1,000 bytes.")
        }
        // A failed recheck must revoke old evidence.
        taskLedger.outcomes[index].evidence = nil
        let operation: (WKWebView) async -> String = { view in
                guard (PageDriver.selectedFrame?.url ?? view.url)?.absoluteString == expectedURL else { return "Verification failed: the page URL does not match." }
                if let ref = controlRef {
                    guard let observationID, !observationID.isEmpty, expectedValue != nil || expectedChecked != nil else {
                        return "Verification failed: provide the control's observationID and its expectedValue or expectedChecked state."
                    }
                    let matched = await PageDriver.$expectedObservation.withValue(observationID) {
                        await PageDriver.verifyControl(ref: ref, value: expectedValue, checked: expectedChecked, in: view)
                    }
                    guard matched else { return "Verification failed: the control is stale, sensitive, or does not match its expected state." }
                    self.taskLedger.outcomes[index].evidence = .init(url: expectedURL, observationID: observationID,
                        matchedText: "Control [\(ref)] matched the expected state", actionRevision: self.taskLedger.actionRevision)
                    self.taskLedger.outcomes[index].blocker = nil
                    if self.taskLedger.completion == .verified {
                        self.taskLedger.pendingAction = nil
                    }
                    return "Condition met. Outcome verified against the current control state."
                }
                let result = await PageDriver.snapshot(view, lookingFor: expectedText)
                guard let observation = PageDriver.observations.object(forKey: view), observation.url == expectedURL,
                      let text = result.components(separatedBy: "\n\nCONTROLS:").first,
                      text.hasPrefix("PAGE TEXT:\n"), String(text.dropFirst("PAGE TEXT:\n".count)).contains(expectedText) else {
                    return "Verification failed: the expected text is not present in the fresh page observation. Inspect the result; do not repeat an uncertain submission."
                }
                self.taskLedger.outcomes[index].evidence = .init(url: expectedURL, observationID: observation.id,
                    matchedText: expectedText, actionRevision: self.taskLedger.actionRevision)
                self.taskLedger.outcomes[index].blocker = nil
                if self.taskLedger.completion == .verified {
                    self.taskLedger.pendingAction = nil
                }
                return "Condition met. Outcome verified against the current page.\n" + result
        }
        let output = await withPageContext(page: page, observationID: nil) {
            if let frameID {
                return await frameOperation(name: "verifyTaskOutcome", frameID: frameID, readOnly: true, operation: operation)
            }
            return await pageOperation(name: "verifyTaskOutcome", readOnly: true, operation: operation)
        }
        if lastToolFailed {
            taskLedger.outcomes[index].evidence = nil
        }
        return output
    }
}
