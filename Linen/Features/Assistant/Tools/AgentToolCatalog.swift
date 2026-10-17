// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentToolDescriptor: Identifiable, Sendable {
    nonisolated enum Category: CaseIterable, Hashable, Sendable {
        case research
        case page
        case tabs
        case media

        var title: LocalizedStringResource {
            switch self {
            case .research:
                "Research"
            case .page:
                "On the Page"
            case .tabs:
                "Tabs"
            case .media:
                "Media"
            }
        }
    }

    let id: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let category: Category
    var isConfigurable = true
}

nonisolated struct AgentToolGroup: Equatable, Sendable {
    let name: String
    let description: String
    let toolIDs: [String]
}

nonisolated enum AgentToolCatalog {
    static let groups: [AgentToolGroup] = [
        .init(name: "research", description: "Search the web, open websites, read page text and controls or just the article, and go back.",
              toolIDs: ["searchWeb", "navigate", "readPage", "readArticle", "goBack"]),
        .init(name: "interaction", description: "Click page controls, fill forms, select options, set checkboxes, scroll, hover, and press keys.",
              toolIDs: ["clickOnPage", "typeOnPage", "fillFields", "selectOption", "setChecked", "scrollPage", "hoverOnPage", "pressKey"]),
        .init(name: "observation", description: "Inspect control state, full field values and dropdown options, wait for page changes, or capture the page viewport.",
              toolIDs: ["inspectControl", "waitForPage", "screenshotPage"]),
        .init(name: "visual", description: "Move, click, double-click, type, or dispatch drag events using screenshot coordinates.",
              toolIDs: ["movePointer", "clickAtPoint", "typeAtPointer", "doubleClickAtPoint", "dragOnPage"]),
        .init(name: "frames", description: "Find embedded websites, request access, and read or interact with their controls.",
              toolIDs: ["listFrames", "readFrame", "actInFrame"]),
        .init(name: "files", description: "Ask the user to choose files for upload or inspect this task's downloads.",
              toolIDs: ["chooseFilesOnPage", "inspectDownloads"]),
        .init(name: "tabs", description: "List, open, switch, and close browser tabs.", toolIDs: ["listTabs", "newTab", "switchTab", "closeTab"]),
        .init(name: "media", description: "Play videos and control or close media playback.", toolIDs: ["playVideo", "closeVideo", "controlMedia"]),
        .init(name: "watches", description: "Watch a page on a schedule and notify the user when it changes, list watches, or stop one.",
              toolIDs: ["watchPage", "listWatches", "stopWatch"]),
    ]

    static let prerequisites: [String: String] = [
        "clickOnPage": "readPage", "typeOnPage": "readPage", "fillFields": "readPage", "selectOption": "readPage",
        "setChecked": "readPage", "hoverOnPage": "readPage", "inspectControl": "readPage", "chooseFilesOnPage": "readPage",
        "readFrame": "listFrames", "actInFrame": "readFrame",
        "movePointer": "screenshotPage", "clickAtPoint": "screenshotPage", "typeAtPointer": "screenshotPage",
        "doubleClickAtPoint": "screenshotPage", "dragOnPage": "screenshotPage",
    ]

    static func withPrerequisites(_ ids: [String], among available: Set<String>) -> [String] {
        var result: [String] = []
        func add(_ id: String) {
            guard available.contains(id), !result.contains(id) else { return }
            if let prerequisite = prerequisites[id] {
                add(prerequisite)
            }
            result.append(id)
        }
        ids.forEach(add)
        return result
    }

    static let controlTools: [String: [String]] = [
        "link": ["clickOnPage"], "button": ["clickOnPage"], "scrollarea": ["scrollPage"],
        "field": ["typeOnPage", "fillFields"], "checkbox": ["setChecked"], "radio": ["setChecked"],
        "select": ["selectOption"], "combobox": ["selectOption"],
    ]

    static func tools(forControlsIn observation: String) -> [String] {
        guard let start = observation.range(of: "CONTROLS:\n") else { return [] }
        var result: [String] = []
        for line in observation[start.upperBound...].split(separator: "\n") {
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let rest = line[line.index(after: close)...].drop { $0 == " " }
            let kind = String(rest.prefix { $0 != " " })
            let ids = kind == "field" && rest.contains("\" (file)") ? ["chooseFilesOnPage"] : controlTools[kind] ?? []
            for id in ids where !result.contains(id) {
                result.append(id)
            }
        }
        return result
    }

    static let requestTools: [(words: Set<String>, tools: [String])] = [
        (["press"], ["pressKey"]), (["key"], ["pressKey"]), (["hover"], ["hoverOnPage"]),
        (["scroll"], ["scrollPage"]), (["bottom"], ["scrollPage"]),
        (["tab"], ["listTabs", "switchTab"]), (["tabs"], ["listTabs", "switchTab"]),
        (["close", "tab"], ["closeTab"]), (["new", "tab"], ["newTab"]),
        (["upload"], ["chooseFilesOnPage"]), (["attach"], ["chooseFilesOnPage"]),
        (["download"], ["inspectDownloads"]), (["downloads"], ["inspectDownloads"]), (["wait"], ["waitForPage"]),
        (["widget"], ["listFrames", "readFrame"]), (["embedded"], ["listFrames", "readFrame"]),
        (["open"], ["navigate"]), (["visit"], ["navigate"]), (["go"], ["navigate"]), (["http"], ["navigate"]), (["https"], ["navigate"]),
        (["www"], ["navigate"]), (["website"], ["navigate"]), (["site"], ["navigate"]),
    ]

    static func tools(forRequest request: String) -> [String] {
        let words = Set(request.lowercased().split { !$0.isLetter }.map(String.init))
        var result: [String] = []
        for entry in requestTools where entry.words.isSubset(of: words) {
            for id in entry.tools where !result.contains(id) {
                result.append(id)
            }
        }
        return result
    }

    static func tools(named ids: some Sequence<String>, in output: String) -> [String] {
        ids.filter { output.contains($0) }
    }

    static func group(containing toolID: String) -> AgentToolGroup? {
        groups.first { $0.toolIDs.contains(toolID) }
    }

    static let all: [AgentToolDescriptor] = [
        AgentToolDescriptor(id: "listFrames", title: "List Embedded Pages", summary: "Find embedded websites on a page.", category: .page),
        AgentToolDescriptor(id: "readFrame", title: "Read Embedded Pages", summary: "Read an embedded website with separate permission.", category: .page),
        AgentToolDescriptor(id: "actInFrame", title: "Use Embedded Pages", summary: "Use controls on a permitted embedded website.", category: .page),
        AgentToolDescriptor(id: "chooseFilesOnPage", title: "Choose Files to Upload", summary: "Ask you to choose files for a website.", category: .page),
        AgentToolDescriptor(id: "inspectDownloads", title: "Check Downloads", summary: "Check whether a task’s downloads finished.", category: .page),
        AgentToolDescriptor(
            id: "searchWeb",
            title: "Search the Web",
            summary: "Look things up with the search engine.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "navigate",
            title: "Open Websites",
            summary: "Open a web address in the active tab.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "readPage",
            title: "Read Pages",
            summary: "Read a page’s text and controls.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "readArticle",
            title: "Read Articles",
            summary: "Read just the main text of an article.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "goBack",
            title: "Go Back",
            summary: "Return to the previous page.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "clickOnPage",
            title: "Click",
            summary: "Press buttons and follow links.",
            category: .page
        ),
        AgentToolDescriptor(
            id: "typeOnPage",
            title: "Type",
            summary: "Fill in search boxes and forms. Never passwords or payment details.",
            category: .page
        ),
        AgentToolDescriptor(
            id: "fillFields",
            title: "Fill Multiple Fields",
            summary: "Fill form controls together without submitting.",
            category: .page
        ),
        AgentToolDescriptor(
            id: "selectOption",
            title: "Choose From Menus",
            summary: "Pick an option in a dropdown menu.",
            category: .page
        ),
        AgentToolDescriptor(
            id: "scrollPage",
            title: "Scroll",
            summary: "Move up or down a page.",
            category: .page
        ),
        AgentToolDescriptor(id: "hoverOnPage", title: "Hover", summary: "Reveal content by hovering over a control.", category: .page),
        AgentToolDescriptor(id: "pressKey", title: "Press Keys", summary: "Use keyboard controls on a page.", category: .page),
        AgentToolDescriptor(id: "inspectControl", title: "Inspect Controls", summary: "Read control state and dropdown options.", category: .page),
        AgentToolDescriptor(id: "setChecked", title: "Set Checkboxes", summary: "Set a checkbox or radio selection.", category: .page),
        AgentToolDescriptor(id: "waitForPage", title: "Wait for Page Changes", summary: "Wait for expected text or loading to finish.", category: .page),
        AgentToolDescriptor(id: "screenshotPage", title: "Capture the Page", summary: "Inspect the current viewport as an image.", category: .page, isConfigurable: false),
        AgentToolDescriptor(id: "movePointer", title: "Move Pointer", summary: "Move a visible pointer over the page.", category: .page, isConfigurable: false),
        AgentToolDescriptor(id: "clickAtPoint", title: "Click Page Point", summary: "Click a point shown in a page screenshot.", category: .page, isConfigurable: false),
        AgentToolDescriptor(id: "typeAtPointer", title: "Type in Focused Field", summary: "Type into a field selected from a screenshot.", category: .page, isConfigurable: false),
        AgentToolDescriptor(id: "doubleClickAtPoint", title: "Double-Click", summary: "Double-click a point in a page screenshot.", category: .page, isConfigurable: false),
        AgentToolDescriptor(id: "dragOnPage", title: "Drag on Page", summary: "Drag between points in a page screenshot.", category: .page, isConfigurable: false),
        AgentToolDescriptor(
            id: "newTab",
            title: "Open Tabs",
            summary: "Open a new tab when you ask for one.",
            category: .tabs
        ),
        AgentToolDescriptor(
            id: "listTabs",
            title: "List Tabs",
            summary: "See the titles of every tab in the window.",
            category: .tabs
        ),
        AgentToolDescriptor(
            id: "switchTab",
            title: "Switch Tabs",
            summary: "Move between the tabs in the conversation.",
            category: .tabs
        ),
        AgentToolDescriptor(
            id: "closeTab",
            title: "Close Tabs",
            summary: "Close a tab in the conversation.",
            category: .tabs
        ),
        AgentToolDescriptor(
            id: "playVideo",
            title: "Play Videos",
            summary: "Find a video and play it in the media player.",
            category: .media
        ),
        AgentToolDescriptor(
            id: "closeVideo",
            title: "Close the Player",
            summary: "Pause the video and close the media player.",
            category: .media
        ),
        AgentToolDescriptor(
            id: "controlMedia",
            title: "Picture in Picture",
            summary: "Move the video into Picture in Picture and back.",
            category: .media
        ),
        AgentToolDescriptor(
            id: "watchPage",
            title: "Watch Pages",
            summary: "Check a page on a schedule and notify you when it changes.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "listWatches",
            title: "List Watched Pages",
            summary: "See which pages are being watched.",
            category: .research
        ),
        AgentToolDescriptor(
            id: "stopWatch",
            title: "Stop Watching",
            summary: "Stop checking a watched page.",
            category: .research
        ),
    ]

    static func descriptors(in category: AgentToolDescriptor.Category) -> [AgentToolDescriptor] {
        all.filter { $0.category == category && $0.isConfigurable }
    }

    static let visualToolIDs: Set<String> = ["screenshotPage", "movePointer", "clickAtPoint", "typeAtPointer", "doubleClickAtPoint", "dragOnPage"]
    static let actionToolIDs: Set<String> = [
        "clickOnPage", "typeOnPage", "fillFields", "selectOption", "setChecked", "pressKey",
        "clickAtPoint", "typeAtPointer", "doubleClickAtPoint", "dragOnPage", "chooseFilesOnPage", "actInFrame",
    ]
    static let configurableIDs = Set(all.filter(\.isConfigurable).map(\.id))

    static let defaultIDs = Set(all.map(\.id))

    static func resolvedIDs(for provider: Provider, settings: LLMSettings = .current) -> Set<String> {
        guard let chosen = settings.enabledAgentTools(for: provider) else {
            return defaultIDs
        }
        let valid = chosen.intersection(configurableIDs)
        return (valid.isEmpty ? defaultIDs : valid).union(defaultIDs.subtracting(configurableIDs))
    }
}

nonisolated extension LLMSettings {
    private static func agentToolsKey(for provider: Provider) -> String {
        "llm.tools.\(provider.id)"
    }

    func enabledAgentTools(for provider: Provider) -> Set<String>? {
        guard let stored = defaults.stringArray(forKey: Self.agentToolsKey(for: provider)) else {
            return nil
        }
        return Set(stored)
    }

    func setEnabledAgentTools(_ ids: Set<String>?, for provider: Provider) {
        if let ids {
            defaults.set(ids.sorted(), forKey: Self.agentToolsKey(for: provider))
        } else {
            defaults.removeObject(forKey: Self.agentToolsKey(for: provider))
        }
    }
}
