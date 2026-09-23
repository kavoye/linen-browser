// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum AgentDiagnosticPrivacy {
    static let tools: Set<String> = [
        "searchWeb", "navigate", "readPage", "clickOnPage", "typeOnPage", "fillFields",
        "selectOption", "scrollPage", "goBack", "askUser", "newTab", "listTabs",
        "switchTab", "closeTab", "playVideo", "closeVideo", "controlMedia",
        "inspectControl", "setChecked", "waitForPage", "screenshotPage", "movePointer", "clickAtPoint", "typeAtPointer", "hoverOnPage", "pressKey",
        "recordTaskOutcome", "verifyTaskOutcome", "blockTaskOutcome", "doubleClickAtPoint", "dragOnPage",
        "listFrames", "readFrame", "actInFrame", "chooseFilesOnPage", "inspectDownloads",
    ]

    static func tool(_ name: String) -> String {
        tools.contains(name) ? name : "custom_tool"
    }

    static func model(_ name: String) -> String {
        let known: Set<String> = [
            "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-astra",
            "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.3-codex",
            "gpt-5.3-codex-spark", "gpt-5.2", "gpt-5.2-codex", "gpt-5.1", "gpt-5",
            "gpt-4.1", "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini", "o3", "o4-mini",
            "claude-sonnet-4-6", "claude-opus-4-6", "claude-opus-4-7", "claude-sonnet-5",
            "gemini-2.5-pro", "gemini-2.5-flash", "gemini-3-pro-preview", "gemini-3-flash-preview",
            "system",
        ]
        return known.contains(name) ? name : "custom_model"
    }

    static func effort(_ name: String) -> String {
        ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].contains(name)
            ? name : "unspecified"
    }

    private static let toolTitles: [String: String] = [
        "recordTaskOutcome": String(localized: "Record task outcome"),
        "verifyTaskOutcome": String(localized: "Verify result"),
        "blockTaskOutcome": String(localized: "Record Unfinished Work"),
        "doubleClickAtPoint": String(localized: "Double-click page"),
        "dragOnPage": String(localized: "Drag on Page"),
        "listFrames": String(localized: "List Embedded Pages"),
        "readFrame": String(localized: "Read embedded page"),
        "actInFrame": String(localized: "Use embedded page"),
        "chooseFilesOnPage": String(localized: "Choose Files to Upload"),
        "inspectDownloads": String(localized: "Check Downloads"),
        "readPage": String(localized: "Read page"),
        "searchWeb": String(localized: "Search web"),
        "navigate": String(localized: "Open page"),
        "typeOnPage": String(localized: "Fill field"),
        "fillFields": String(localized: "Fill fields"),
        "clickOnPage": String(localized: "Click control"),
        "selectOption": String(localized: "Select option"),
        "inspectControl": String(localized: "Inspect control"),
        "setChecked": String(localized: "Set checked state"),
        "waitForPage": String(localized: "Wait for page"),
        "screenshotPage": String(localized: "Capture page"),
        "movePointer": String(localized: "Move Pointer"),
        "clickAtPoint": String(localized: "Click page"),
        "typeAtPointer": String(localized: "Type on page"),
        "hoverOnPage": String(localized: "Reveal hover content"),
        "pressKey": String(localized: "Press key"),
        "askUser": String(localized: "Ask user"),
        "scrollPage": String(localized: "Scroll page"),
        "goBack": String(localized: "Go Back"),
        "newTab": String(localized: "Open tab"),
        "listTabs": String(localized: "List Tabs"),
        "switchTab": String(localized: "Switch tab"),
        "closeTab": String(localized: "Close Tab"),
        "playVideo": String(localized: "Control media"),
        "closeVideo": String(localized: "Control media"),
        "controlMedia": String(localized: "Control media"),
    ]

    static func title(for tool: String) -> String {
        toolTitles[tool] ?? String(localized: "Use tool")
    }
}

nonisolated struct AgentRunDiagnostics: Codable, Equatable, Sendable {
    var model = "custom_model"
    var reasoningEffort = "unspecified"
    var modelRequests = 0
    var toolCalls = 0
    var failedToolCalls = 0
    var compactions = 0
    var elapsedMilliseconds = 0
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedTokens: Int?
    var cacheWriteTokens: Int?
    var reasoningTokens: Int?
    var providerUsageRequests: Int?
    var events: [AgentEvaluationEvent] = []

    mutating func record(_ event: AgentEvaluationEvent) {
        switch event.kind {
        case "provider_usage":
            let first = (providerUsageRequests ?? 0) == 0
            func total(_ old: Int?, _ key: String) -> Int? {
                guard let value = event.values[key].flatMap(Int.init), value >= 0 else { return nil }
                guard first || old != nil else { return nil }
                let (sum, overflow) = (old ?? 0).addingReportingOverflow(value)
                return overflow ? nil : sum
            }
            inputTokens = total(inputTokens, "input_tokens")
            outputTokens = total(outputTokens, "output_tokens")
            cachedTokens = total(cachedTokens, "cached_tokens")
            cacheWriteTokens = total(cacheWriteTokens, "cache_write_tokens")
            reasoningTokens = total(reasoningTokens, "reasoning_tokens")
            providerUsageRequests = (providerUsageRequests ?? 0) + 1
        case "generation":
            modelRequests += 1
        case "tool_accepted":
            toolCalls += 1
        case "tool_failed":
            failedToolCalls += 1
        case "context_compaction":
            compactions += 1
        default:
            break
        }
        events.append(event)
        if events.count > 256 {
            events.removeFirst(events.count - 256)
        }
    }

    func exported() -> String {
        var safe = self
        safe.model = AgentDiagnosticPrivacy.model(model)
        safe.reasoningEffort = AgentDiagnosticPrivacy.effort(reasoningEffort)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(safe)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
