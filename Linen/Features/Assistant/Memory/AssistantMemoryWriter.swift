// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

enum AssistantMemoryWriter {
    @Generable
    struct Change {
        @Guide(description: "A short lowercase noun for what the note is about, such as interests, diet, shoe size or usual lamp colour. Reuse an existing subject to update it.")
        var subject: String
        @Guide(description: "A few words, such as cars, vegetarian, 42 or Brass. Never the whole sentence. Empty when forgetting.")
        var value: String
        @Guide(description: "True only when the user asks you to forget this note.")
        var forget: Bool
    }

    @Generable
    struct Changes {
        @Guide(description: "The notes to add, update or forget. Empty when the user said nothing lasting about themselves.")
        var changes: [Change]
    }

    static let instructions = """
        You keep short notes about the user for a browser assistant. You get what the user typed in this \
        conversation, their answers to the assistant's questions, and the notes you already have. Note lasting \
        facts the user states about themselves: preferences, interests, dislikes, sizes, diet, allergies, home \
        city, and what they usually choose. Follow requests to remember or forget something. Skip details of \
        the current task, facts about other people, and passwords, payment details or ID numbers. To change a \
        note, reuse its subject. For a list such as interests, keep the earlier items in the value. Return no \
        changes when nothing lasting was said.
        """

    static func prompt(said: String, notes: [AssistantMemory.Fact]) -> String {
        let existing = notes.isEmpty ? "None" : notes.prefix(30).map { "- \($0.subject): \($0.value)" }.joined(separator: "\n")
        return "NOTES YOU HAVE:\n\(existing)\n\nWHAT THE USER SAID:\n\(said)"
    }

    static func changes(said: String, notes: [AssistantMemory.Fact], model: any LanguageModel) async -> [Change] {
        guard !said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            return try await session.respond(to: prompt(said: said, notes: notes), generating: Changes.self).content.changes
        } catch {
            Pipeline.log.error("Memory notes could not be written")
            return []
        }
    }
}
