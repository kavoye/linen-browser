// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct CommandPaletteModelTests {
    @Test func openStartPageCommandCreatesAStartPageTab() throws {
        let coordinator = AppCoordinator()
        let previous = coordinator.browser.newTab()
        previous.urlString = "https://example.com/"
        let count = coordinator.browser.tabs.count
        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
        model.prepare()
        model.interaction.query = "> start"

        let command = try #require(model.sections.flattened.first { $0.id == "action-openStartPage" })
        #expect(command.title == "Open Start Page")
        command.run()

        #expect(coordinator.browser.tabs.count == count + 1)
        #expect(coordinator.browser.activeTab !== previous)
        #expect(coordinator.browser.activeTab?.hasNoPageYet == true)
        #expect(ChromeBand.showsStartPage(browser: coordinator.browser))
    }

    @Test func newTabPaletteCreatesTabOnlyWhenOpeningAResult() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            let coordinator = AppCoordinator()
            let active = coordinator.browser.newTab()
            let count = coordinator.browser.tabs.count
            let model = CommandPaletteModel(
                browser: coordinator.browser,
                coordinator: coordinator
            ) {}
            model.prepare()
            #expect(coordinator.browser.tabs.count == count)

            model.interaction.query = "https://example.com/new-tab-palette"
            let result = try #require(model.sections.flattened.first { $0.id == "omnibox-go" })
            result.run()

            #expect(coordinator.browser.tabs.count == count + 1)
            #expect(coordinator.browser.activeTab !== active)
            #expect(coordinator.browser.activeTab?.urlString == "https://example.com/new-tab-palette")
        }
    }

    @Test func newTabPaletteSearchCreatesTabAndTabMatchSwitchesWithoutCreatingOne() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            let coordinator = AppCoordinator()
            let existing = coordinator.browser.newTab()
            existing.title = "Existing page"
            let active = coordinator.browser.newTab()
            let count = coordinator.browser.tabs.count
            let model = CommandPaletteModel(
                browser: coordinator.browser,
                coordinator: coordinator
            ) {}
            model.prepare()

            let tabResult = try #require(model.sections.flattened.first { $0.id == "tab-\(existing.id)" })
            tabResult.run()
            #expect(coordinator.browser.activeTab?.id == existing.id)
            #expect(coordinator.browser.tabs.count == count)

            model.interaction.query = "winter hiking boots"
            let searchResult = try #require(model.sections.flattened.first { $0.id == "omnibox-search" })
            searchResult.run()
            #expect(coordinator.browser.tabs.count == count + 1)
            #expect(coordinator.browser.activeTab?.id != existing.id)
            #expect(coordinator.browser.activeTab?.id != active.id)
        }
    }

    @Test func optionReturnOpensTheSelectedWebResultInTheCurrentTab() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            let coordinator = AppCoordinator()
            let active = coordinator.browser.newTab()
            let count = coordinator.browser.tabs.count
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
            model.prepare()
            model.interaction.query = "https://example.com/current-tab"

            model.submitInCurrentTab()

            #expect(coordinator.browser.tabs.count == count)
            #expect(coordinator.browser.activeTab === active)
            #expect(active.urlString == "https://example.com/current-tab")
        }
    }

    @Test func currentPageCanBeMentionedInThePalette() throws {
        try Omnibox.$agentOnlyForTesting.withValue(true) {
            let coordinator = AppCoordinator()
            let current = coordinator.browser.newTab()
            current.urlString = "https://shop.example/current"
            current.title = "Current item"
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
            model.prepare()
            model.interaction.query = "compare @current"

            let item = try #require(model.sections.flattened.first { $0.id == "mention-\(current.id)" })
            item.run()

            #expect(model.mentionedTabIDs == [current.id])
            #expect(MentionText.resolved(model.interaction.query, chips: model.mentionChips) == "compare @Current item ")
            model.interaction.query += "@current"
            #expect(!model.sections.flattened.contains { $0.id == "mention-\(current.id)" })
        }
    }

    @Test func suggestionPreviewKeepsResultsStableUntilTypingResumes() throws {
        try Omnibox.$agentOnlyForTesting.withValue(true) {
            let coordinator = AppCoordinator()
            let tab = coordinator.browser.newTab()
            tab.urlString = "https://example.com/full/path?q=value#section"
            tab.title = "Example page"
            var dismissed = false
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {
                dismissed = true
            }
            model.prepare()
            let ids = model.sections.flattened.map(\.id)
            let tabIndex = try #require(model.sections.flattened.firstIndex { $0.id == "tab-\(tab.id)" })
            let actionIndex = try #require(model.sections.flattened.firstIndex { $0.kind == .action })

            model.selectSuggestion(at: tabIndex)
            #expect(model.interaction.query == tab.urlString)
            #expect(model.resultQuery.isEmpty)
            model.suggestionsDidChange()
            #expect(model.sections.flattened.map(\.id) == ids)
            #expect(model.interaction.selection == tabIndex)

            model.selectSuggestion(at: actionIndex)
            #expect(model.interaction.query.isEmpty)
            model.moveSelection(by: tabIndex - actionIndex)
            #expect(model.interaction.query == tab.urlString)
            #expect(!dismissed)

            model.interaction.query += "extra"
            #expect(model.resultQuery == tab.urlString + "extra")
            #expect(model.interaction.selection == 0)
            #expect(model.sections.flattened.map(\.id) != ids)
        }
    }

    @Test func hoveringATabDoesNotReplaceTypedQuery() throws {
        try Omnibox.$agentOnlyForTesting.withValue(true) {
            let coordinator = AppCoordinator()
            let activeTab = coordinator.browser.newTab()
            let tab = coordinator.browser.newTab()
            tab.urlString = "https://some.example/page"
            tab.title = "Some page"
            coordinator.browser.activate(activeTab)
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
            model.prepare()
            model.interaction.query = "s"
            let tabIndex = try #require(model.sections.flattened.firstIndex { $0.id == "omnibox-tab-\(tab.id)" })

            model.hoverSuggestion(at: tabIndex)

            #expect(model.interaction.query == "s")
            #expect(model.interaction.selection == tabIndex)
            model.interaction.query += "earch"
            #expect(model.interaction.query == "search")
            #expect(model.resultQuery == "search")
        }
    }

    @Test func arrivingSuggestionsKeepTheSelectedResult() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            let coordinator = AppCoordinator()
            let tab = coordinator.browser.newTab()
            tab.title = "Project tab"
            let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
            model.prepare()
            model.interaction.query = "project"
            let selectedID = "omnibox-tab-\(tab.id)"
            let index = try #require(model.sections.flattened.firstIndex { $0.id == selectedID })
            model.hoverSuggestion(at: index)

            model.suggestions.store(["project ideas", "project plan"], for: "project", engine: SearchURLBuilder.engine)
            model.suggestionsDidChange()

            #expect(model.sections.flattened[model.interaction.selection].id == selectedID)
            #expect(model.sections.first { $0.id == "suggestions" }?.items.count == 2)
        }
    }

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
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "t"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .shift, key: "p"))
        #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: [], key: "p"))

        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .command, key: "l"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .control, key: "f"))
        #expect(CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: "p"))
    }

    @Test func paletteShortcutsToggleAndNewTabSelectionTracksThePalette() {
        let coordinator = AppCoordinator()
        let tab = coordinator.browser.newTab()
        coordinator.browser.sidebarSelection.toggle(.tab(tab.id))

        coordinator.togglePalette()
        #expect(coordinator.isPaletteOpen)
        #expect(!coordinator.isNewTabPaletteOpen)
        let token = coordinator.paletteToken

        coordinator.togglePalette()
        #expect(!coordinator.isPaletteOpen)
        #expect(coordinator.paletteToken == token)

        coordinator.requestNewTab()
        #expect(coordinator.isPaletteOpen)
        #expect(coordinator.isNewTabPaletteOpen)
        #expect(coordinator.browser.sidebarSelection.isEmpty)
        #expect(coordinator.browser.tabs.count == 1)
        #expect(coordinator.paletteToken == token + 1)

        coordinator.requestNewTab()
        #expect(!coordinator.isPaletteOpen)
        #expect(!coordinator.isNewTabPaletteOpen)

        coordinator.requestNewTab()
        #expect(coordinator.isNewTabPaletteOpen)
        coordinator.togglePalette()
        #expect(!coordinator.isPaletteOpen)
        #expect(!coordinator.isNewTabPaletteOpen)
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

            #expect(sections.map(\.id) == ["top", "suggestions", "tabs", "history"])
            #expect(sections.first { $0.id == "top" }?.items.map(\.id) == ["omnibox-search", "ask-agent"])
            #expect(sections.first { $0.id == "top" }?.items.last?.detail == "Ask Assistant")
            #expect(sections.first { $0.id == "tabs" }?.items.count == 4)
            #expect(sections.first { $0.id == "history" }?.items.count == 3)
            #expect(sections.first { $0.id == "suggestions" }?.items.count == 3)
            #expect(sections.flattened.count == CommandPaletteBudget.typing)
        }
    }

    @Test func paletteHasOneSearchResultWithACurrentTabAlternate() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "hell",
                agentName: "Assistant",
                history: fixtureHistory(count: 0),
                tabs: [],
                phrases: ["hello"],
                actions: noOpActions()
            )

            let top = sections.first { $0.id == "top" }
            #expect(top?.items.map(\.id) == ["omnibox-search", "ask-agent"])
            #expect(top?.items.first?.symbol == OmniboxItem.Kind.newTab.defaultSymbol)
            #expect(top?.items.first?.alternate != nil)
            #expect(!sections.flattened.contains { $0.id == "omnibox-new-tab" })
            #expect(sections.first { $0.id == "suggestions" }?.items.first?.alternate != nil)

            let addressSections = CommandPaletteProjection.sections(
                query: "example.com",
                agentName: "Assistant",
                history: fixtureHistory(count: 0),
                tabs: [],
                phrases: [],
                actions: noOpActions()
            )
            #expect(addressSections.first?.items.first?.symbol == OmniboxItem.Kind.newTab.defaultSymbol)
        }
    }

    @Test func holdingOptionChangesTheWebRowButNotTheAskRow() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            let sections = CommandPaletteProjection.sections(
                query: "example.com",
                agentName: "Assistant",
                history: fixtureHistory(count: 0),
                tabs: [],
                phrases: [],
                actions: noOpActions()
            )
            let web = try #require(sections.first?.items.first)
            let ask = try #require(sections.first?.items.dropFirst().first)

            #expect(OmniboxRowPresentation(item: web, optionHeld: false).symbol == OmniboxItem.Kind.newTab.defaultSymbol)
            let current = OmniboxRowPresentation(item: web, optionHeld: true)
            #expect(current.symbol == "arrow.up.right")
            #expect(current.detail == String(localized: "Open website in current tab"))
            #expect(current.replacesFavicon)
            #expect(OmniboxRowPresentation(item: ask, optionHeld: true).detail == "Ask Assistant")
        }
    }

    @Test func webResultsShareNewTabAndCurrentTabActions() throws {
        try Omnibox.$agentOnlyForTesting.withValue(false) {
            var newTabURLs: [URL] = []
            var currentTabURLs: [URL] = []
            var actions = noOpActions()
            actions.openNew = { newTabURLs.append($0) }
            actions.openCurrent = { currentTabURLs.append($0) }
            let sections = CommandPaletteProjection.sections(
                query: "project",
                agentName: "Assistant",
                history: fixtureHistory(count: 1),
                tabs: [],
                phrases: ["project suggestion"],
                actions: actions
            )

            for id in ["omnibox-search", "omnibox-phrase-project suggestion"] {
                let item = try #require(sections.flattened.first { $0.id == id })
                item.run()
                item.alternate?()
            }
            let historyItem = try #require(sections.first { $0.id == "history" }?.items.first)
            historyItem.run()
            historyItem.alternate?()

            #expect(newTabURLs.count == 3)
            #expect(currentTabURLs == newTabURLs)
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

            #expect(sections.map(\.id) == ["top"])
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

            #expect(sections.map(\.id) == ["top"])
            #expect(sections.first?.items.first?.id == "omnibox-go")
            #expect(sections.first?.items.last?.id == "ask-agent")
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
                "action-openStartPage", "action-organizeTabs", "action-toggleSpeech",
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

    @Test func restingOpenTabsFollowActivationOrder() throws {
        let coordinator = AppCoordinator()
        let tabs = (0..<7).map { _ in coordinator.browser.newTab(activate: false) }
        coordinator.browser.activate(tabs[0])
        coordinator.browser.activate(tabs[2])

        let model = CommandPaletteModel(browser: coordinator.browser, coordinator: coordinator) {}
        model.prepare()
        let openTabs = try #require(model.sections.first { $0.id == "tabs" }).items

        #expect(openTabs.count == 5)
        #expect(openTabs.prefix(2).map(\.id) == ["tab-\(tabs[2].id)", "tab-\(tabs[0].id)"])
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

    @Test func menuNavigationAndFindCommandsAreInTheCatalog() {
        var context = fixtureContext()
        context.canGoBack = true
        let commands = CommandPaletteCatalog.commands(context: context) { _ in }
        let byID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        let expected: [(CommandPaletteAction, String, String)] = [
            (.openLocation, "Open Location…", "⌘L"),
            (.nextTab, "Show Next Tab", "⇧⌘]"),
            (.previousTab, "Show Previous Tab", "⇧⌘["),
            (.lastTab, "Show Last Tab", "⌘9"),
            (.findNext, "Find Next", "⌘G"),
            (.findPrevious, "Find Previous", "⇧⌘G"),
            (.minimizeWindow, "Minimize", "⌘M"),
            (.closeWindow, "Close Window", "⇧⌘W"),
            (.quitLinen, "Quit Linen", "⌘Q"),
        ]
        for (action, title, shortcut) in expected {
            let command = byID["action-\(action.rawValue)"]
            #expect(command?.title == title)
            #expect(command?.shortcut == shortcut)
        }
        #expect(byID["action-showTab1"]?.title == "Show Tab 1")
        #expect(byID["action-showTab6"]?.shortcut == "⌘6")
        #expect(byID["action-showTab7"]?.id == nil)
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
            #expect(sections.first?.items.map(\.id) == ["omnibox-search", "ask-agent"])
            #expect(sections.first { $0.id == "actions" }?.items.first?.id == "action-organizeTabs")
            #expect(sections.dropFirst(2).first?.id == "suggestions")
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

            #expect(sections.map(\.id) == ["top", "actions"])
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
            #expect(all.flattened.contains { $0.id == "action-openStartPage" })

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
            #expect(!CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: .command, key: key))
        }
    }

    /// ⌥↩ opens web results in the current tab, while ⌘↩ asks the assistant.
    @Test func optionReturnRunsTheRowInTheCurrentTab() {
        for key in CommandPaletteShortcutPolicy.returnKeys {
            #expect(CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: .option, key: key))
            #expect(!CommandPaletteShortcutPolicy.shouldDismiss(modifiers: .option, key: key))
        }
        #expect(!CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: .option, key: "a"))
        #expect(!CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: [], key: "\r"))
        #expect(!CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: [.option, .command], key: "\r"))
        #expect(!CommandPaletteShortcutPolicy.opensInCurrentTab(modifiers: .shift, key: "\r"))
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
