// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

extension AnyLanguageModelAgent {
    static let continuationPrompt = "Continue the task using the tool result."
    static let stepPrompt = "Use the tool result. If it completes the request, answer the user now. Otherwise take the next step."
    static let answerPrompt = "Answer the user now, in plain words."
    static let readStreakPrompt = """
        You read the page several times without finding anything new. If the request needs an action, \
        take it with the right tool. Otherwise answer with what you found, and say plainly what you did not do.
        """
    static let scaffoldingPrompts: Set<String> = [continuationPrompt, stepPrompt, answerPrompt, readStreakPrompt]

    static func isScaffolding(_ text: String) -> Bool {
        scaffoldingPrompts.contains(text) || text == recoveryPrompt || text.hasPrefix(readStreakPrompt)
    }

    func readStreakPrompt(for transcript: Transcript) -> String {
        let offered = Set(tools(for: transcript).map(\.name))
        var suggested: [String] = []
        for entry in transcript {
            switch entry {
            case .prompt(let prompt) where !Self.isScaffolding(Self.text(in: prompt.segments)):
                suggested = AgentToolCatalog.tools(forRequest: Self.text(in: prompt.segments))
            case .toolOutput(let output):
                suggested += AgentToolCatalog.tools(forControlsIn: Self.text(in: output.segments)).filter { !suggested.contains($0) }
            default:
                break
            }
        }
        var actions = suggested.filter { offered.contains($0) && !AgentProgressMonitor.readOnlyTools.contains($0) }
        if let preference = toolkit.pendingPreference {
            return Self.readStreakPrompt + " The request mentions “\(preference)”, which only the user knows: ask them with askUser."
        }
        actions = actions.filter { $0 != "askUser" }
        return actions.isEmpty ? Self.readStreakPrompt : Self.readStreakPrompt + " Tools you can act with now: " + actions.joined(separator: ", ") + "."
    }

    static func earlierFinding(about subject: String, not other: String = "", in transcript: Transcript) -> String? {
        let wanted = subject.lowercased()
        let unwanted = other.lowercased()
        for entry in transcript.reversed() {
            guard case .toolOutput(let output) = entry else { continue }
            let text = text(in: output.segments)
            guard let start = text.range(of: "PAGE TEXT:\n") else { continue }
            let body = text[start.upperBound...]
            let lines = (body.range(of: "\n\n").map { body[..<$0.lowerBound] } ?? body).split(separator: "\n")
            let opening = lines.prefix(3).map { $0.lowercased() }
            guard opening.contains(where: { $0.contains(wanted) }), unwanted.isEmpty || !opening.contains(where: { $0.contains(unwanted) }) else { continue }
            return String(lines.prefix(5).joined(separator: "\n").prefix(300))
        }
        return nil
    }

    func withheldTools(afterRepeatedRead repeated: Bool) -> Set<String> {
        repeated && defersTools ? ["readPage", "readArticle"] : []
    }

    static let recoveryPrompt = """
        Recent actions returned the same result or failed repeatedly. Read the current page for \
        fresh controls, inspect validation messages, and change your approach. Do not repeat the \
        same unsuccessful action. If you need the user, ask a specific question with askUser.
        """

    func currentInstructions(_ transcript: Transcript, tools: [any Tool]) -> Transcript {
        var entries = Array(transcript)
        guard let index = entries.firstIndex(where: { if case .instructions = $0 { return true }; return false }),
              case .instructions(let stored) = entries[index]
        else { return transcript }
        var fresh = Transcript.Instructions(
            segments: [.text(.init(content: instructionsText))],
            toolDefinitions: tools.filter(\.includesSchemaInInstructions).map { Transcript.ToolDefinition(tool: $0) }
        )
        fresh.segments += stored.segments.filter {
            if case .text(let text) = $0 {
                return text.id == Self.resumeInstructionID
            }
            return false
        }
        entries[index] = .instructions(fresh)
        return Transcript(entries: entries)
    }
}
