// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum OpenAIToolSearch {
    private struct Group {
        let name: String
        let description: String
        let functions: Set<String>
    }

    private static let groups: [Group] = [
        .init(name: "browser_research", description: "Search the web, open websites, read page text and controls, and go back.",
              functions: ["searchWeb", "navigate", "readPage", "goBack"]),
        .init(name: "browser_interaction", description: "Click page controls, fill forms, select options, set checkboxes, scroll, hover, and press keys.",
              functions: ["clickOnPage", "typeOnPage", "fillFields", "selectOption", "setChecked", "scrollPage", "hoverOnPage", "pressKey"]),
        .init(name: "browser_observation", description: "Inspect control state and dropdown options, wait for page changes, or capture the page viewport.",
              functions: ["inspectControl", "waitForPage", "screenshotPage"]),
        .init(name: "browser_tabs", description: "List, open, switch, and close browser tabs.", functions: ["listTabs", "newTab", "switchTab", "closeTab"]),
        .init(name: "browser_media", description: "Play videos and control or close media playback.", functions: ["playVideo", "closeVideo", "controlMedia"]),
    ]

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
            !groups.contains { $0.functions.contains(function["name"].string ?? "") }
        }
        var deferred = false
        for group in groups {
            let members = functions.filter { $0["type"] == "function" && group.functions.contains($0["name"].string ?? "") }
            guard !members.isEmpty else { continue }
            result.append([
                "type": "namespace", "name": .string(group.name), "description": .string(group.description),
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
