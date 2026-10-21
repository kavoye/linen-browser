// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

@MainActor
final class AgentToolLoader {
    private var cache: (key: [String], names: [String])?

    static func loader(for available: [any Tool], defers: Bool) -> LoadToolsTool? {
        guard defers else { return nil }
        let deferrable = available.filter { AgentToolDeferral.isDeferrable($0.name) }
        return deferrable.isEmpty ? nil : LoadToolsTool(tools: deferrable)
    }

    func tools(from available: [any Tool], defers: Bool, for transcript: Transcript, schemaTokens: Int) -> [any Tool] {
        guard let loader = Self.loader(for: available, defers: defers) else { return available }
        let always = available.filter { !AgentToolDeferral.isDeferrable($0.name) } + [loader]
        let byName = Dictionary(available.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let key = Self.key(for: transcript) + loader.toolNames
        if let cache, cache.key == key {
            return always + cache.names.compactMap { byName[$0] }
        }
        let names = Set(loader.toolNames)
        var recent: [String] = []
        var requested: [String] = []
        func touch(_ ids: [String]) {
            for id in AgentToolCatalog.withPrerequisites(ids, among: names) {
                recent.removeAll { $0 == id }
                recent.append(id)
            }
        }
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                touch(instructions.toolDefinitions.map(\.name))
            case .toolCalls(let calls):
                for call in calls {
                    touch(call.toolName == LoadToolsTool.toolName ? LoadToolsTool.requestedTools(in: call.arguments) : [call.toolName])
                }
            case .prompt(let prompt):
                let text = TranscriptMetrics.text(in: prompt.segments)
                if !AnyLanguageModelAgent.isScaffolding(text) {
                    requested = AgentToolCatalog.tools(forRequest: text)
                }
            case .toolOutput(let output):
                let text = TranscriptMetrics.text(in: output.segments)
                let controls = ["readFrame", "actInFrame"].contains(output.toolName) ? [] : AgentToolCatalog.tools(forControlsIn: text)
                let opens = output.toolName == "searchWeb" ? ["navigate"] : []
                touch(controls + opens + AgentToolCatalog.tools(named: loader.toolNames, in: text))
            default:
                break
            }
        }
        touch(requested)
        let cap = schemaTokens - estimatedToolSchemaTokens(always)
        var loaded = recent.compactMap { byName[$0] }
        while loaded.count > 1, estimatedToolSchemaTokens(loaded) > cap {
            loaded.removeFirst()
        }
        cache = (key, loaded.map(\.name))
        return always + loaded
    }

    private static func key(for transcript: Transcript) -> [String] {
        transcript.map { entry in
            switch entry {
            case .instructions(let instructions):
                instructions.toolDefinitions.map(\.name).joined(separator: ",")
            case .toolOutput(let output):
                "\(output.id):\(TranscriptMetrics.text(in: output.segments).utf8.count)"
            default:
                entry.id
            }
        }
    }
}
