// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import WebKit

struct CommandPaletteActions {
    var openCurrent: (URL) -> Void = { _ in }
    var ask: (String) -> Void = { _ in }
    var switchTo: (BrowserTab) -> Void = { _ in }
    var close: ((BrowserTab) -> Void)?
    var mention: (BrowserTab) -> Void = { _ in }
    var openNew: (URL) -> Void = { _ in }
    var perform: (CommandPaletteAction) -> Void = { _ in }
}

enum CommandPaletteProjection {
    static let commandPrefix = ">"

    static func placeholder(agentOnly: Bool) -> String {
        let resource: LocalizedStringResource = agentOnly
            ? "Search tabs, history, actions, or ask"
            : "Search tabs, history, actions, or the web"
        return String(localized: resource)
    }

    static func suggestionQuery(for query: String) -> String {
        commandQuery(in: query) == nil ? query : ""
    }

    static func isAssistantQuery(_ query: String, hasMentions: Bool, agentOnly: Bool) -> Bool {
        if hasMentions {
            return true
        }

        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return false }
        if AskSurfaceInteraction.agentPrompt(in: input) != nil {
            return true
        }
        return agentOnly && Omnibox.location(for: input) == nil
    }

    static func opensArchive(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 3 else { return false }
        return "archived tabs".hasPrefix(query)
            || query.count > "show ".count && "show archived tabs".hasPrefix(query)
    }

    static func commandQuery(in query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.hasPrefix(commandPrefix) else { return nil }
        return String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sections(
        query: String,
        agentName: String,
        context: CommandPaletteContext = CommandPaletteContext(),
        history: HistoryStore,
        tabs: [BrowserTab],
        mentions: [MentionChip] = [],
        activeTabID: UUID? = nil,
        recentTabIDs: [UUID] = [],
        phrases: [String],
        settings: BrowserSettings = .shared,
        actions: CommandPaletteActions
    ) -> [OmniboxSection] {
        let commands = CommandPaletteCatalog.commands(context: context, perform: actions.perform)

        if let command = commandQuery(in: query) {
            guard !command.isEmpty else { return CommandPaletteCatalog.groupedSections(commands) }
            return [actionsSection(CommandPaletteCatalog.matching(command, in: commands))].compactMap { $0 }
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return restingSections(
                history: history,
                tabs: tabs,
                activeTabID: activeTabID,
                recentTabIDs: recentTabIDs,
                commands: commands,
                actions: actions
            )
        }

        if AskSurfaceInteraction.mentionFragment(in: query) != nil {
            return AskSurfaceResults.sections(
                placement: .startPage,
                query: query,
                isFocused: true,
                isListening: false,
                currentURL: "",
                agentOnly: false,
                agentName: agentName,
                history: history,
                tabs: tabs,
                mentions: mentions,
                activeTabID: activeTabID,
                phrases: [],
                settings: settings,
                open: { _ in },
                switchTo: { _ in },
                mention: actions.mention,
                ask: { _ in }
            )
        }

        if let prompt = AskSurfaceInteraction.agentPrompt(in: needle) {
            return prompt.isEmpty ? [] : [askSection(prompt, agentName: agentName, ask: actions.ask)]
        }

        if !mentions.isEmpty {
            let prompt = MentionText.resolved(needle, chips: mentions)
            return [askSection(prompt, agentName: agentName, ask: actions.ask)]
        }

        let webItems = Omnibox.topSection(
            query: needle,
            symbol: OmniboxItem.Kind.newTab.defaultSymbol,
            openInCurrentTab: actions.openCurrent,
            settings: settings,
            open: actions.openNew
        )?.items ?? []
        let slots = [
            CommandPaletteBudget.Slot(
                OmniboxSection(
                    id: "top",
                    title: "",
                    items: webItems + [askItem(needle, agentName: agentName, ask: actions.ask)]
                ),
                floor: 1,
                quota: 2
            ),
            CommandPaletteBudget.Slot(
                Omnibox.phrasesSection(
                    query: needle,
                    phrases: phrases,
                    limit: 3,
                    openInCurrentTab: actions.openCurrent,
                    settings: settings,
                    open: actions.openNew
                ),
                floor: 2,
                quota: 3
            ),
            CommandPaletteBudget.Slot(
                Omnibox.pagesSection(
                    query: needle,
                    tabs: tabs,
                    hiding: activeTabID,
                    store: history,
                    limit: 5,
                    switchTo: actions.switchTo,
                    close: actions.close,
                    openInCurrentTab: actions.openCurrent,
                    open: actions.openNew
                ),
                floor: 5,
                quota: 5
            ),
            CommandPaletteBudget.Slot(
                actionsSection(CommandPaletteCatalog.matching(needle, in: commands)),
                floor: 1,
                quota: 3
            ),
        ]

        return CommandPaletteBudget.fit(slots, total: CommandPaletteBudget.typing)
    }

    private static func askSection(
        _ prompt: String,
        agentName: String,
        ask: @escaping (String) -> Void
    ) -> OmniboxSection {
        OmniboxSection(
            id: "ask",
            title: "",
            items: [askItem(prompt, agentName: agentName, ask: ask)]
        )
    }

    private static func askItem(
        _ prompt: String,
        agentName: String,
        ask: @escaping (String) -> Void
    ) -> OmniboxItem {
        OmniboxItem(
            id: "ask-agent",
            kind: .ask,
            title: prompt,
            detail: String(localized: "Ask \(agentName)"),
            shortcut: "⌘↩"
        ) {
            ask(prompt)
        }
    }

    private static func actionsSection(_ commands: [CommandPaletteCommand], hint: String = "") -> OmniboxSection? {
        guard !commands.isEmpty else { return nil }
        return OmniboxSection(
            id: "actions",
            title: String(localized: "Actions"),
            hint: hint,
            items: CommandPaletteCatalog.items(commands)
        )
    }

    private static func restingSections(
        history: HistoryStore,
        tabs: [BrowserTab],
        activeTabID: UUID?,
        recentTabIDs: [UUID],
        commands: [CommandPaletteCommand],
        actions: CommandPaletteActions
    ) -> [OmniboxSection] {
        let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let recentlyUsedTabs = recentTabIDs.compactMap { tabsByID[$0] }
        let recentlyUsedIDs = Set(recentlyUsedTabs.map(\.id))
        let orderedTabs = (recentlyUsedTabs + tabs.filter { !recentlyUsedIDs.contains($0.id) })
            .filter { $0.id != activeTabID }
        let openURLs = Set(tabs.map(\.urlString))
        let unopened = Array(history.entries
            .lazy
            .filter { !openURLs.contains($0.url) }
            .compactMap { entry in
                Omnibox.historyItem(
                    entry,
                    id: "recent-\(entry.id)",
                    store: history,
                    openInCurrentTab: actions.openCurrent,
                    open: actions.openNew
                )
            }
            .prefix(5))
        let tabCount = min(orderedTabs.count, 5 - min(unopened.count, 2))
        let openTabs = orderedTabs.prefix(tabCount).map { tab in
            Omnibox.tabItem(tab, id: "tab-\(tab.id)", switchTo: actions.switchTo, close: actions.close)
        }
        let recent = unopened.prefix(5 - tabCount)

        let slots = [
            CommandPaletteBudget.Slot(
                OmniboxSection(id: "pages", title: String(localized: "Pages"), items: openTabs + recent),
                floor: 5,
                quota: 5
            ),
            CommandPaletteBudget.Slot(
                actionsSection(
                    CommandPaletteCatalog.suggested(commands),
                    hint: String(localized: "Type > for commands")
                ),
                floor: 3,
                quota: 5
            ),
        ]
        return CommandPaletteBudget.fit(slots, total: CommandPaletteBudget.resting)
    }
}
