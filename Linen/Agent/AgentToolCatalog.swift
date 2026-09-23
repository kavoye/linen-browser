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
    let isCore: Bool
    var isConfigurable = true
}

nonisolated enum AgentToolCatalog {
    static let all: [AgentToolDescriptor] = [
        AgentToolDescriptor(id: "recordTaskOutcome", title: "Record Task Outcomes", summary: "Keep track of each requested result.", category: .page, isCore: true, isConfigurable: false),
        AgentToolDescriptor(id: "verifyTaskOutcome", title: "Verify Results", summary: "Check the page for the requested result.", category: .page, isCore: true, isConfigurable: false),
        AgentToolDescriptor(id: "blockTaskOutcome", title: "Record Unfinished Work", summary: "Save why an outcome needs your help.", category: .page, isCore: true, isConfigurable: false),
        AgentToolDescriptor(id: "listFrames", title: "List Embedded Pages", summary: "Find embedded websites on a page.", category: .page, isCore: false),
        AgentToolDescriptor(id: "readFrame", title: "Read Embedded Pages", summary: "Read an embedded website with separate permission.", category: .page, isCore: false),
        AgentToolDescriptor(id: "actInFrame", title: "Use Embedded Pages", summary: "Use controls on a permitted embedded website.", category: .page, isCore: false),
        AgentToolDescriptor(id: "chooseFilesOnPage", title: "Choose Files to Upload", summary: "Ask you to choose files for a website.", category: .page, isCore: false),
        AgentToolDescriptor(id: "inspectDownloads", title: "Check Downloads", summary: "Check whether a task's downloads finished.", category: .page, isCore: false),
        AgentToolDescriptor(
            id: "searchWeb",
            title: "Search the Web",
            summary: "Look things up with the search engine.",
            category: .research,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "navigate",
            title: "Open Websites",
            summary: "Open a web address in the active tab.",
            category: .research,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "readPage",
            title: "Read Pages",
            summary: "Read a page’s text and controls.",
            category: .research,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "goBack",
            title: "Go Back",
            summary: "Return to the previous page.",
            category: .research,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "clickOnPage",
            title: "Click",
            summary: "Press buttons and follow links.",
            category: .page,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "typeOnPage",
            title: "Type",
            summary: "Fill in search boxes and forms. Never passwords or payment details.",
            category: .page,
            isCore: true
        ),
        AgentToolDescriptor(
            id: "fillFields",
            title: "Fill Multiple Fields",
            summary: "Fill several text fields or dropdowns together without submitting.",
            category: .page,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "selectOption",
            title: "Choose From Menus",
            summary: "Pick an option in a dropdown menu.",
            category: .page,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "scrollPage",
            title: "Scroll",
            summary: "Move up or down a page.",
            category: .page,
            isCore: true
        ),
        AgentToolDescriptor(id: "hoverOnPage", title: "Hover", summary: "Reveal content by hovering over a control.", category: .page, isCore: false),
        AgentToolDescriptor(id: "pressKey", title: "Press Keys", summary: "Use keyboard controls on a page.", category: .page, isCore: false),
        AgentToolDescriptor(id: "inspectControl", title: "Inspect Controls", summary: "Read control state and dropdown options.", category: .page, isCore: false),
        AgentToolDescriptor(id: "setChecked", title: "Set Checkboxes", summary: "Set a checkbox or radio selection.", category: .page, isCore: false),
        AgentToolDescriptor(id: "waitForPage", title: "Wait for Page Changes", summary: "Wait for expected text or loading to finish.", category: .page, isCore: false),
        AgentToolDescriptor(id: "screenshotPage", title: "Capture the Page", summary: "Inspect the current viewport as an image.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(id: "movePointer", title: "Move Pointer", summary: "Move a visible pointer over the page.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(id: "clickAtPoint", title: "Click Page Point", summary: "Click a point shown in a page screenshot.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(id: "typeAtPointer", title: "Type in Focused Field", summary: "Type into a field selected from a screenshot.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(id: "doubleClickAtPoint", title: "Double-Click", summary: "Double-click a point in a page screenshot.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(id: "dragOnPage", title: "Drag on Page", summary: "Drag between points in a page screenshot.", category: .page, isCore: false, isConfigurable: false),
        AgentToolDescriptor(
            id: "newTab",
            title: "Open Tabs",
            summary: "Open a new tab when you ask for one.",
            category: .tabs,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "listTabs",
            title: "List Tabs",
            summary: "See the titles of every tab in the window.",
            category: .tabs,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "switchTab",
            title: "Switch Tabs",
            summary: "Move between the tabs in the conversation.",
            category: .tabs,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "closeTab",
            title: "Close Tabs",
            summary: "Close a tab in the conversation.",
            category: .tabs,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "playVideo",
            title: "Play Videos",
            summary: "Find a video and play it in the media player.",
            category: .media,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "closeVideo",
            title: "Close the Player",
            summary: "Pause the video and close the media player.",
            category: .media,
            isCore: false
        ),
        AgentToolDescriptor(
            id: "controlMedia",
            title: "Picture in Picture",
            summary: "Move the video into Picture in Picture and back.",
            category: .media,
            isCore: false
        ),
    ]

    static func descriptors(in category: AgentToolDescriptor.Category) -> [AgentToolDescriptor] {
        all.filter { $0.category == category && $0.isConfigurable }
    }

    static let visualToolIDs: Set<String> = ["screenshotPage", "movePointer", "clickAtPoint", "typeAtPointer", "doubleClickAtPoint", "dragOnPage"]
    static let outcomeToolIDs: Set<String> = ["recordTaskOutcome", "verifyTaskOutcome", "blockTaskOutcome"]
    static let configurableIDs = Set(all.filter(\.isConfigurable).map(\.id))

    static func defaultIDs(for tier: AgentToolTier) -> Set<String> {
        switch tier {
        case .core:
            Set(all.filter(\.isCore).map(\.id))
        case .full:
            Set(all.map(\.id))
        }
    }

    static func resolvedIDs(for provider: Provider, tier: AgentToolTier) -> Set<String> {
        let known = Set(all.map(\.id))
        guard let chosen = LLMSettings.enabledAgentTools(for: provider) else {
            return defaultIDs(for: tier)
        }
        let valid = chosen.intersection(known).subtracting(visualToolIDs)
        let selected = valid.isEmpty ? defaultIDs(for: tier) : valid
        return tier == .full ? selected.union(visualToolIDs) : selected
    }
}

nonisolated extension LLMSettings {
    private static func agentToolsKey(for provider: Provider) -> String {
        "llm.tools.\(provider.id)"
    }

    static func enabledAgentTools(for provider: Provider) -> Set<String>? {
        guard let stored = defaults.stringArray(forKey: agentToolsKey(for: provider)) else {
            return nil
        }
        return Set(stored)
    }

    static func setEnabledAgentTools(_ ids: Set<String>?, for provider: Provider) {
        if let ids {
            defaults.set(ids.sorted(), forKey: agentToolsKey(for: provider))
        } else {
            defaults.removeObject(forKey: agentToolsKey(for: provider))
        }
    }
}
