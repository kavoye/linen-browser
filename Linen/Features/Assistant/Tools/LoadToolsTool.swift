// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

nonisolated enum AgentToolDeferral {
    enum Mode: Sendable {
        case smallWindows
        case always
        case never
    }

    @TaskLocal static var mode = Mode.smallWindows

    static let loadedToolReserve = 1_000
    static let alwaysLoaded: Set<String> = ["readPage", "goBack"]

    static func applies(toWindow windowTokens: Int) -> Bool {
        switch mode {
        case .smallWindows:
            ContextBudget.isSmall(windowTokens)
        case .always:
            true
        case .never:
            false
        }
    }

    static func isDeferrable(_ name: String) -> Bool {
        !alwaysLoaded.contains(name) && AgentToolCatalog.group(containing: name) != nil
    }

    static func initialTools(from available: [any Tool]) -> [any Tool] {
        let deferrable = available.filter { isDeferrable($0.name) }
        guard !deferrable.isEmpty else { return available }
        return available.filter { !isDeferrable($0.name) } + [LoadToolsTool(tools: deferrable)]
    }

    static func schemaTokens(for available: [any Tool]) -> Int {
        estimatedToolSchemaTokens(initialTools(from: available)) + loadedToolReserve
    }
}

nonisolated struct LoadToolsTool: Tool {
    typealias Arguments = GeneratedContent
    static let toolName = "loadTools"
    let name = LoadToolsTool.toolName
    let toolNames: [String]

    init(tools: [any Tool]) {
        toolNames = tools.map(\.name)
    }

    var description: String {
        "Load the browser tools a step needs before you call them; each is named for what it does. "
            + "Load several at once when you can. Tools unused for a while are unloaded; load them again when needed."
    }

    var parameters: GenerationSchema {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "tools": [
                    "type": "array", "description": "The tools to load", "minItems": 1,
                    "items": ["type": "string", "enum": toolNames],
                ],
            ],
            "required": ["tools"],
            "additionalProperties": false,
        ]
        return (try? JSONSerialization.data(withJSONObject: schema)).flatMap { try? JSONDecoder().decode(GenerationSchema.self, from: $0) }
            ?? GenerationSchema(type: GeneratedContent.self, properties: [.init(name: "tools", type: [String].self)])
    }

    static func requestedTools(in arguments: GeneratedContent) -> [String] {
        (try? arguments.value([String].self, forProperty: "tools")) ?? []
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let names = AgentToolCatalog.withPrerequisites(Self.requestedTools(in: arguments), among: Set(toolNames))
        guard !names.isEmpty else {
            return "Name at least one tool from the list."
        }
        return "Loaded. You can now call " + names.joined(separator: ", ") + "."
    }
}
