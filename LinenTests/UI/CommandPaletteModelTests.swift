// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct CommandPaletteModelTests {
    /// The palette walks the same way the ask surface does: arrows wrap, so
    /// up from the first row reaches the last one.
    @Test func selectionWrapsAndAChangedQueryReturnsToTheFirstRow() {
        var interaction = CommandPaletteInteraction(query: "first", selection: 2)

        interaction.moveSelection(by: 1, resultCount: 4)
        #expect(interaction.selection == 3)
        interaction.moveSelection(by: 1, resultCount: 4)
        #expect(interaction.selection == 0)
        interaction.moveSelection(by: -1, resultCount: 4)
        #expect(interaction.selection == 3)
        interaction.moveSelection(by: -2, resultCount: 4)
        #expect(interaction.selection == 1)

        interaction.clampSelection(to: 1)
        #expect(interaction.selection == 0)
        interaction.selection = 3
        interaction.clampSelection(to: 0)
        #expect(interaction.selection == 0)

        interaction.selection = 2
        interaction.query = "second"
        #expect(interaction.selection == 0)
    }

    @Test func layoutStaysCentredAndRespectsNarrowWindowMargins() {
        let standard = CommandPaletteLayout(containerSize: CGSize(width: 1_200, height: 900))
        #expect(standard.panelWidth == 600)
        #expect(standard.maxListHeight == 420)
        #expect(standard.topInset == 209)

        let narrow = CommandPaletteLayout(containerSize: CGSize(width: 520, height: 300))
        #expect(narrow.panelWidth == 440)
        #expect(narrow.maxListHeight == 158)
        #expect(narrow.topInset == 40)
    }

    @Test func shortcutPolicyKeepsEditingAndPaletteCommandsOpen() {
        for key in ["a", "c", "v", "x", "z", "A"] {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: key))
        }
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "k"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .shift, key: "p"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [], key: "p"))

        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "l"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .control, key: "f"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: "p"))
    }

    /// A modified arrow is the palette moving its own selection. Dismissing on
    /// it is what took command-arrow section jumps away.
    @Test func aModifiedArrowStaysWithTheList() {
        for key in CommandPaletteShortcutPolicy.arrowKeys {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [], key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: key))
        }
        #expect(CommandPaletteShortcutPolicy.arrowKeys.count == 4)
    }

    /// Command-arrow moves by section, and the sections it counts are the ones
    /// the palette is showing.
    @Test func commandArrowJumpsBetweenTheSectionsOnScreen() {
        var interaction = CommandPaletteInteraction(query: "org", selection: 0)
        let counts = [1, 0, 3, 2]

        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 1)
        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 4)
        interaction.moveSection(by: 1, itemCounts: counts)
        #expect(interaction.selection == 0)
        interaction.moveSection(by: -1, itemCounts: counts)
        #expect(interaction.selection == 4)
    }

    @Test func placeholderExplainsTheCurrentInputMode() {
        #expect(
            CommandPaletteProjection.placeholder(agentOnly: false)
                == String(localized: "Search tabs, history, actions, or the web")
        )
        #expect(
            CommandPaletteProjection.placeholder(agentOnly: true)
                == String(localized: "Search tabs, history, actions, or ask")
        )
    }

    @Test func normalQueryHasStableOrderingAndBoundedGroups() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let history = fixtureHistory(count: 12)
            let tabs = fixtureTabs(count: 8)
            let sections = CommandPaletteProjection.sections(
                query: "project",
                agentName: "Assistant",
                history: history,
                tabs: tabs,
                phrases: (0..<10).map { "project suggestion \($0)" },
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["top", "ask", "tabs", "history", "suggestions"])
            // The top hit and the same hit in a new tab.
            #expect(sections.first { $0.id == "top" }?.items.count == 2)
            #expect(sections.first { $0.id == "tabs" }?.items.count == 3)
            #expect(sections.first { $0.id == "history" }?.items.count == 3)
            #expect(sections.first { $0.id == "suggestions" }?.items.count == 3)
            #expect(sections.flattened.count == CommandPaletteBudget.typing)
        }
    }

    @Test func theAtPrefixAsksInsteadOfSearching() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "@ what is a spline",
                agentName: "Assistant",
                history: fixtureHistory(count: 12),
                tabs: fixtureTabs(count: 8),
                phrases: ["what is a spline"],
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["ask"])
            #expect(sections.first?.items.first?.title == "what is a spline")
        }
    }

    @Test func anAttachedTabLeavesOnlyTheAskResult() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let tabs = fixtureTabs(count: 8)
            let sections = CommandPaletteProjection.sections(
                query: "project",
                agentName: "Assistant",
                history: fixtureHistory(count: 12),
                tabs: tabs,
                mentions: [MentionChip(id: tabs[0].id, title: tabs[0].title)],
                phrases: (0..<10).map { "project suggestion \($0)" },
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["ask"])
            #expect(sections.first?.items.first?.title == "project")
        }
    }

    @Test func agentOnlyProseShowsAskWithoutWebSuggestions() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let sections = CommandPaletteProjection.sections(
                query: "compare these workstreams",
                agentName: "Assistant",
                history: HistoryStore(database: .temporary()),
                tabs: [],
                phrases: ["compare these workstreams online"],
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["ask"])
        }
    }

    @Test func agentOnlyLinksStillOfferNavigationBeforeAsk() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let sections = CommandPaletteProjection.sections(
                query: "example.com",
                agentName: "Assistant",
                history: HistoryStore(database: .temporary()),
                tabs: [],
                phrases: [],
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["top", "ask"])
            #expect(sections.first?.items.first?.id == "omnibox-go")
        }
    }

    @Test func restingResultsExcludeOpenPagesAndCapBothGroups() {
        let history = HistoryStore(database: .temporary(), windowSize: 50)
        let tabs = fixtureTabs(count: 8)
        for tab in tabs {
            history.record(url: tab.urlString, title: "Open \(tab.title)")
        }
        for index in 0..<8 {
            history.record(url: "https://recent-\(index).example/", title: "Recent \(index)")
        }

        let sections = CommandPaletteProjection.sections(
            query: "",
            agentName: "Assistant",
            context: fixtureContext(),
            history: history,
            tabs: tabs,
            phrases: [],
            actions: noOpActions()
        )

        #expect(sections.map(\.id) == ["tabs", "actions", "recent"])
        #expect(sections[1].items.allSatisfy { item in
            [
                "action-newTab", "action-organizeTabs", "action-toggleSpeech",
                "action-clearHistory", "action-settings",
            ].contains(item.id)
        })
        #expect(sections[0].items.count == 5)
        #expect(sections[2].items.count == 4)
        #expect(sections.flattened.count == CommandPaletteBudget.resting)
        #expect(sections[1].hint == String(localized: "Type > for commands"))
        let openURLs = Set(tabs.map(\.urlString))
        #expect(sections[2].items.allSatisfy { item in
            !openURLs.contains { item.detail.contains(URL(string: $0)?.displayHost ?? $0) }
        })
    }

    @Test func actionRowsRunTheInjectedCommand() {
        var performed: [CommandPaletteAction] = []
        var actions = noOpActions()
        actions.perform = { performed.append($0) }

        let sections = CommandPaletteProjection.sections(
            query: "settings",
            agentName: "Assistant",
            history: HistoryStore(database: .temporary()),
            tabs: [],
            phrases: [],
            actions: actions
        )
        let settings = sections.first { $0.id == "actions" }?.items.first

        #expect(settings?.id == "action-settings")
        #expect(settings?.shortcut == "⌘,")
        settings?.run()
        #expect(performed == [.settings])
    }

    @Test func aQueryThatNamesACommandLiftsItAboveThePages() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "organize",
                agentName: "Assistant",
                context: fixtureContext(),
                history: fixtureHistory(count: 4),
                tabs: fixtureTabs(count: 4),
                phrases: ["organize my life"],
                actions: noOpActions()
            )

            #expect(sections.map(\.id).prefix(2) == ["top", "actions"])
            #expect(sections.first { $0.id == "actions" }?.items.first?.id == "action-organizeTabs")
            #expect(sections.last?.id == "suggestions")
        }
    }

    @Test func outOfOrderWordsStillNameTheCommand() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "tabs organize",
                agentName: "Assistant",
                context: fixtureContext(),
                history: HistoryStore(database: .temporary()),
                tabs: [],
                phrases: [],
                actions: noOpActions()
            )

            #expect(sections.map(\.id).prefix(2) == ["top", "actions"])
        }
    }

    @Test func aWeakCommandMatchStaysBelowThePages() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "ogt",
                agentName: "Assistant",
                context: fixtureContext(),
                history: HistoryStore(database: .temporary()),
                tabs: [],
                phrases: [],
                actions: noOpActions()
            )

            #expect(sections.map(\.id) == ["top", "ask", "actions"])
            #expect(sections.last?.items.first?.id == "action-organizeTabs")
        }
    }

    @Test func theCommandPrefixTypesTheListDownToCommands() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let all = CommandPaletteProjection.sections(
                query: ">",
                agentName: "Assistant",
                context: fixtureContext(),
                history: fixtureHistory(count: 6),
                tabs: fixtureTabs(count: 6),
                phrases: ["project suggestion"],
                actions: noOpActions()
            )
            #expect(all.map(\.id).prefix(3) == ["actions-tabs", "actions-page", "actions-view"])
            #expect(all.flattened.count > 20)
            #expect(all.flattened.contains { $0.id == "action-newTab" })

            let filtered = CommandPaletteProjection.sections(
                query: "> org",
                agentName: "Assistant",
                context: fixtureContext(),
                history: fixtureHistory(count: 6),
                tabs: fixtureTabs(count: 6),
                phrases: ["project suggestion"],
                actions: noOpActions()
            )
            #expect(filtered.map(\.id) == ["actions"])
            #expect(filtered.first?.items.first?.id == "action-organizeTabs")
        }
    }

    @Test func aCommandQueryIsNeverSentAwayToBeCompleted() {
        #expect(CommandPaletteProjection.suggestionQuery(for: "weather") == "weather")
        #expect(CommandPaletteProjection.suggestionQuery(for: ">weather").isEmpty)
        #expect(CommandPaletteProjection.suggestionQuery(for: "  > weather ").isEmpty)
        #expect(CommandPaletteProjection.commandQuery(in: ">") == "")
        #expect(CommandPaletteProjection.commandQuery(in: "a > b") == nil)
    }

    /// ⌘↩ asks the assistant, the way it does in the address field, and the
    /// field claims it. Dismissing would take the key before it got there.
    @Test func commandReturnStaysWithThePalette() {
        for key in CommandPaletteShortcutPolicy.returnKeys {
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: key))
            #expect(!CommandPaletteShortcutPolicy.opensInNewTab(modifiers: .command, key: key))
        }
    }

    /// ⇧↩ is the second destination, so ⌘↩ can stay on the assistant.
    @Test func shiftReturnRunsTheRowInANewTab() {
        for key in CommandPaletteShortcutPolicy.returnKeys {
            #expect(CommandPaletteShortcutPolicy.opensInNewTab(modifiers: .shift, key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .shift, key: key))
        }
        #expect(!CommandPaletteShortcutPolicy.opensInNewTab(modifiers: .shift, key: "a"))
        #expect(!CommandPaletteShortcutPolicy.opensInNewTab(modifiers: [], key: "\r"))
        #expect(!CommandPaletteShortcutPolicy.opensInNewTab(modifiers: [.shift, .command], key: "\r"))
    }

    private func fixtureContext() -> CommandPaletteContext {
        CommandPaletteContext(historyCount: 12, tabCount: 6, hasActiveTab: true)
    }

    private func fixtureHistory(count: Int) -> HistoryStore {
        let history = HistoryStore(database: .temporary(), windowSize: max(count, 20))
        for index in 0..<count {
            history.record(
                url: "https://docs.example/project/\(index)",
                title: "Project documentation \(index)"
            )
        }
        return history
    }

    private func fixtureTabs(count: Int) -> [BrowserTab] {
        (0..<count).map { index in
            let tab = BrowserTab()
            tab.title = "Project tab \(index)"
            tab.urlString = "https://tabs.example/project/\(index)"
            return tab
        }
    }

    private func noOpActions() -> CommandPaletteActions {
        CommandPaletteActions()
    }
}
