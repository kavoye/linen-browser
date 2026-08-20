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
}

nonisolated enum AgentToolCatalog {
    static let all: [AgentToolDescriptor] = [
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
            summary: "Go to a web address in the research page.",
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
        AgentToolDescriptor(
            id: "newTab",
            title: "Open Tabs",
            summary: "Open a new tab when you ask for one.",
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
        all.filter { $0.category == category }
    }

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
        let valid = chosen.intersection(known)
        return valid.isEmpty ? defaultIDs(for: tier) : valid
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
