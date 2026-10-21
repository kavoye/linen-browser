// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

extension AgentToolkit {
    func beginRequest(_ utterance: String) {
        let request = Self.userText(of: utterance)
        requestConstraints = AgentRequestConstraints(request: request)
        turn.userWords = [request]
    }

    func resumeRequest(_ utterance: String, answers: [String]) {
        let request = Self.userText(of: utterance)
        requestConstraints = AgentRequestConstraints(request: request)
        turn.userWords = [request] + answers
        turn.askedUser = !answers.isEmpty
    }

    nonisolated static func userText(of utterance: String) -> String {
        guard utterance.hasPrefix("[Pages in context:"), let end = utterance.range(of: "]\n") else { return utterance }
        return String(utterance[end.upperBound...])
    }

    var remembersUser: Bool {
        AssistantMemory.isEnabled
    }

    func rememberedContext() -> String {
        let remembered = remembersUser ? AssistantMemory.context(for: Array(browser.memory.facts.prefix(20))) : ""
        guard let preference = pendingPreference else { return remembered }
        return remembered + "[The request mentions “\(preference)”, which you do not know. Ask the user with askUser before you change anything.]\n"
    }

    var pendingPreference: String? {
        guard let preference = requestConstraints.preference, !turn.askedUser else { return nil }
        return remembersUser && browser.memory.fact(about: preference) != nil ? nil : preference
    }

    func writeMemory(using model: any LanguageModel) async {
        guard remembersUser else { return }
        let said = turn.userWords.filter { !$0.isEmpty }.joined(separator: "\n")
        let changes = await AssistantMemoryWriter.changes(said: said, notes: browser.memory.facts, model: model)
        for change in changes {
            if change.forget {
                if let fact = browser.memory.facts.first(where: { $0.subject.caseInsensitiveCompare(change.subject) == .orderedSame })
                    ?? browser.memory.fact(about: change.subject) {
                    browser.memory.forget(fact.id)
                }
            } else if browser.memory.facts.first(where: { $0.subject.caseInsensitiveCompare(change.subject) == .orderedSame })?.value != change.value {
                rememberFact(change.subject, is: change.value, source: .message)
            }
        }
    }

    @discardableResult
    func rememberFact(_ subject: String, is value: String, source: AssistantMemory.Fact.Source) -> AgentMemoryUpdate? {
        guard remembersUser, let fact = browser.memory.remember(subject, is: value, source: source) else { return nil }
        let update = AgentMemoryUpdate(factID: fact.id, subject: fact.subject, value: fact.value)
        turn.memoryUpdates.removeAll { $0.factID == fact.id }
        turn.memoryUpdates.append(update)
        return update
    }

    func preferenceRefusal(for toolName: String) -> String? {
        if let preference = requestConstraints.preference, remembersUser, browser.memory.fact(about: preference) != nil {
            return nil
        }
        guard let preference = requestConstraints.preference, !turn.askedUser, !turn.preferenceReminded,
              ["clickOnPage", "typeOnPage", "fillFields", "selectOption", "setChecked"].contains(toolName)
        else { return nil }
        turn.preferenceReminded = true
        return "This request depends on \(preference), which only the user knows. Nothing was changed. Ask them with askUser first."
    }
}
