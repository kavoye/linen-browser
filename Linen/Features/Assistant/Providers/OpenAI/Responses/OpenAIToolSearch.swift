// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum OpenAIToolSearch {
    @TaskLocal static var isAllowed = true

    static func supports(_ model: String) -> Bool {
        let parts = model.lowercased().split(separator: "-")
        guard parts.count >= 2, parts[0] == "gpt" else { return false }
        let version = parts[1].split(separator: ".")
        guard let major = version.first.flatMap({ Int($0) }) else { return false }
        return major >= 6 || (major == 5 && version.count >= 2 && (Int(version[1]) ?? 0) >= 4)
    }

    static func definitions(_ functions: [OpenAIJSON], enabled: Bool) -> [OpenAIJSON] {
        guard enabled else { return functions }
        var result = functions.filter { function in
            AgentToolCatalog.group(containing: function["name"].string ?? "") == nil
        }
        var deferred = false
        for group in AgentToolCatalog.groups {
            let members = functions.filter { $0["type"] == "function" && group.toolIDs.contains($0["name"].string ?? "") }
            guard !members.isEmpty else { continue }
            result.append([
                "type": "namespace", "name": .string("browser_" + group.name), "description": .string(group.description),
                "tools": .array(members.map { function in
                    var function = function
                    function["defer_loading"] = true
                    return function
                }),
            ])
            deferred = true
        }
        if deferred { result.append(["type": "tool_search"]) }
        return result
    }

    static func validateNamespace(_ call: OpenAIJSON, definitions: [OpenAIJSON]) throws {
        if call["namespace"] == .null { return }
        guard let namespace = call["namespace"].string else { throw OpenAIFailure(kind: .invalidResponse) }
        guard definitions.contains(where: {
            $0["type"] == "namespace" && $0["name"].string == namespace &&
                ($0["tools"].array ?? []).contains { $0["type"] == "function" && $0["name"] == call["name"] }
        }) else { throw OpenAIFailure(kind: .unsupportedAction) }
    }

    static func validateHostedEvent(_ item: OpenAIJSON) throws {
        guard item["execution"] == "server", item["call_id"] == .null, item["status"] == "completed" else {
            throw OpenAIFailure(kind: .unsupportedAction)
        }
    }
}
