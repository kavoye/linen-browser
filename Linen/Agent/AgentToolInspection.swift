// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

struct AgentToolInspection {
    let input: String?
    let result: String?
    let imageCount: Int

    static func forTrace(_ trace: ConversationLog.TaskTrace) -> [UUID: Self] {
        guard let checkpoint = trace.checkpoint else { return [:] }
        var calls: [Transcript.ToolCall] = []
        var outputs: [String: Transcript.ToolOutput] = [:]
        for entry in checkpoint.transcript {
            switch entry {
            case .toolCalls(let batch):
                calls.append(contentsOf: batch)
            case .toolOutput(let output):
                outputs[output.id] = output
            default:
                break
            }
        }

        var inspections: [UUID: Self] = [:]
        var cursor = calls.count
        for step in trace.steps.reversed() where step.kind == .tool {
            while cursor > 0 {
                cursor -= 1
                let call = calls[cursor]
                guard AgentDiagnosticPrivacy.tool(call.toolName) == step.toolName else { continue }
                let output = outputs[call.id]
                inspections[step.id] = Self(
                    input: input(for: call),
                    result: output.flatMap { result(for: $0, tool: call.toolName) },
                    imageCount: output?.segments.filter {
                        if case .image = $0 {
                            return true
                        }
                        return false
                    }.count ?? 0
                )
                break
            }
        }
        return inspections
    }

    private static func input(for call: Transcript.ToolCall) -> String? {
        guard AgentDiagnosticPrivacy.tool(call.toolName) != "custom_tool", call.toolName != "askUser",
              let data = call.arguments.jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: redacted(object), options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8), text != "{}"
        else { return nil }
        return preview(text, limit: 2_000)
    }

    private static func redacted(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return array.map(redacted)
        }
        guard let dictionary = value as? [String: Any] else { return value }
        return dictionary.reduce(into: [String: Any]()) { result, entry in
            let key = entry.key.lowercased()
            if ["text", "expectedtext", "value", "expectedvalue", "answer", "password", "token", "secret", "authorization", "apikey"].contains(key) {
                result[entry.key] = "[hidden]"
            } else if ["url", "href"].contains(key), let raw = entry.value as? String {
                var parts = URLComponents(string: raw)
                parts?.user = nil
                parts?.password = nil
                parts?.query = nil
                parts?.fragment = nil
                result[entry.key] = parts?.host == nil ? "[hidden]" : (parts?.string ?? "[hidden]")
            } else {
                result[entry.key] = redacted(entry.value)
            }
        }
    }

    private static func result(for output: Transcript.ToolOutput, tool: String) -> String? {
        if tool == "askUser" || AgentDiagnosticPrivacy.tool(tool) == "custom_tool" {
            return String(localized: "Tool result hidden.")
        }
        var text = output.segments.compactMap { segment -> String? in
            if case .text(let value) = segment {
                return value.content
            }
            return nil
        }.joined(separator: "\n")
        text = text.replacingOccurrences(of: "<page-content untrusted=\"true\">", with: "")
            .replacingOccurrences(of: "</page-content>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ["typeOnPage", "fillFields", "typeAtPointer"].contains(tool),
           let range = text.range(of: "PAGE TEXT:") {
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : preview(text, limit: 4_000)
    }

    private static func preview(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…"
    }
}
