// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct CommandPaletteRankingTests {

    @Test func floorsArePaidFirstAndTheRemainderGoesRound() {
        let fitted = CommandPaletteBudget.fit(
            [
                CommandPaletteBudget.Slot(section("top", count: 1), floor: 1, quota: 1),
                CommandPaletteBudget.Slot(section("tabs", count: 9), floor: 2, quota: 4),
                CommandPaletteBudget.Slot(section("history", count: 9), floor: 2, quota: 5),
                CommandPaletteBudget.Slot(section("suggestions", count: 9), floor: 2, quota: 3),
            ],
            total: 12
        )

        #expect(fitted.map(\.id) == ["top", "tabs", "history", "suggestions"])
        #expect(fitted.map(\.items.count) == [1, 4, 4, 3])
    }

    @Test func anEmptyGroupIsDroppedRatherThanReserved() {
        let fitted = CommandPaletteBudget.fit(
            [
                CommandPaletteBudget.Slot(nil, floor: 2, quota: 4),
                CommandPaletteBudget.Slot(section("tabs", count: 0), floor: 2, quota: 4),
                CommandPaletteBudget.Slot(section("history", count: 6), floor: 2, quota: 5),
            ],
            total: 12
        )

        #expect(fitted.map(\.id) == ["history"])
        #expect(fitted.first?.items.count == 5)
    }

    @Test func anOverspentBudgetTakesRowsFromTheBottom() {
        let fitted = CommandPaletteBudget.fit(
            [
                CommandPaletteBudget.Slot(section("tabs", count: 4), floor: 4, quota: 4),
                CommandPaletteBudget.Slot(section("history", count: 4), floor: 4, quota: 4),
                CommandPaletteBudget.Slot(section("suggestions", count: 4), floor: 4, quota: 4),
            ],
            total: 6
        )

        #expect(fitted.map(\.id) == ["tabs", "history"])
        #expect(fitted.map(\.items.count) == [4, 2])
    }

    @Test func aGroupNeverGrowsPastWhatItHas() {
        let fitted = CommandPaletteBudget.fit(
            [CommandPaletteBudget.Slot(section("tabs", count: 2), floor: 1, quota: 8)],
            total: 40
        )

        #expect(fitted.first?.items.count == 2)
    }

    @Test func theHeaderAndItsHintSurviveTheTrim() {
        let full = OmniboxSection(id: "actions", title: "Actions", hint: "Type > for commands", items: items(5))
        let fitted = CommandPaletteBudget.fit(
            [CommandPaletteBudget.Slot(full, floor: 1, quota: 5)],
            total: 2
        )

        #expect(fitted.first?.title == "Actions")
        #expect(fitted.first?.hint == "Type > for commands")
        #expect(fitted.first?.items.count == 2)
    }

    @Test func aBetterNameForTheCommandScoresHigher() throws {
        let command = fixtureCommand()
        let exact = try #require(CommandMatch.score(command, for: "organize tabs"))
        let prefix = try #require(CommandMatch.score(command, for: "organ"))
        let word = try #require(CommandMatch.score(command, for: "tabs"))
        let scattered = try #require(CommandMatch.score(command, for: "ogtb"))

        #expect(exact > prefix)
        #expect(prefix > word)
        #expect(word > scattered)
        #expect(word >= CommandMatch.strong)
        #expect(scattered < CommandMatch.strong)
    }

    @Test func theWordsMayArriveInAnyOrder() throws {
        let command = fixtureCommand()
        let reversed = try #require(CommandMatch.score(command, for: "tabs organize"))

        #expect(reversed >= CommandMatch.strong)
    }

    @Test func twoStrayLettersAreNotAMatch() {
        #expect(CommandMatch.score(fixtureCommand(), for: "oz") == nil)
        #expect(CommandMatch.score(fixtureCommand(), for: "xyz") == nil)
    }

    @Test func anAliasFindsTheCommandButRanksUnderItsName() throws {
        let command = fixtureCommand()
        let alias = try #require(CommandMatch.score(command, for: "tidy"))
        let name = try #require(CommandMatch.score(command, for: "organize"))

        #expect(alias > 0)
        #expect(name > alias)
    }

    @Test func theBestNamedCommandIsListedFirst() {
        let commands = CommandPaletteCatalog.commands(context: fixtureContext(), perform: { _ in })
        let matched = CommandPaletteCatalog.matching("tab", in: commands)

        #expect(matched.first?.id == "action-newTab")
        #expect(matched.contains { $0.id == "action-organizeTabs" })
        #expect(CommandPaletteCatalog.matching("zzqq", in: commands).isEmpty)
        #expect(CommandPaletteCatalog.bestScore("zzqq", in: commands) == 0)
    }

    @Test func aCommandIsFoundByTheWordAPersonWouldReachFor() {
        let commands = CommandPaletteCatalog.commands(context: fixtureContext(), perform: { _ in })

        for word in ["preferences", "config", "api key"] {
            #expect(CommandPaletteCatalog.matching(word, in: commands).first?.id == "action-settings")
        }
        #expect(CommandPaletteCatalog.matching("mute", in: commands).first?.id == "action-toggleSpeech")
        #expect(CommandPaletteCatalog.matching("forget", in: commands).first?.id == "action-clearHistory")
        #expect(CommandPaletteCatalog.matching("incognito", in: commands).first?.id == "action-privateBrowsing")
        #expect(CommandPaletteCatalog.matching("bookmark", in: commands).first?.id == "action-togglePin")
        #expect(CommandPaletteCatalog.matching("refresh", in: commands).first?.id == "action-reload")
    }

    @Test func aCommandTheBrowserCannotRunIsNotOffered() {
        let empty = CommandPaletteCatalog.commands(context: CommandPaletteContext(), perform: { _ in })
        let ids = Set(empty.map(\.id))

        #expect(!ids.contains("action-closeTab"))
        #expect(!ids.contains("action-goBack"))
        #expect(!ids.contains("action-stopLoading"))
        #expect(!ids.contains("action-clearHistory"))
        #expect(!ids.contains("action-exitSplit"))
        #expect(ids.contains("action-newTab"))
        #expect(ids.contains("action-settings"))

        let loaded = CommandPaletteCatalog.commands(
            context: CommandPaletteContext(
                historyCount: 3,
                tabCount: 2,
                hasActiveTab: true,
                canGoBack: true,
                isLoading: true,
                isSplit: true
            ),
            perform: { _ in }
        )
        let loadedIDs = Set(loaded.map(\.id))

        #expect(loadedIDs.isSuperset(of: [
            "action-closeTab", "action-goBack", "action-stopLoading", "action-clearHistory", "action-exitSplit",
        ]))
        #expect(!loadedIDs.contains("action-goForward"))
    }

    @Test func aToggleIsNamedForWhatItWillDo() {
        let quiet = CommandPaletteCatalog.commands(
            context: CommandPaletteContext(isSpeechMuted: true),
            perform: { _ in }
        )
        let loud = CommandPaletteCatalog.commands(
            context: CommandPaletteContext(isSpeechMuted: false, isSidebarVisible: false),
            perform: { _ in }
        )

        #expect(quiet.first { $0.id == "action-toggleSpeech" }?.title == String(localized: "Enable Voice"))
        #expect(loud.first { $0.id == "action-toggleSpeech" }?.title == String(localized: "Disable Voice"))
        #expect(quiet.first { $0.id == "action-toggleActivity" }?.title == String(localized: "Show Assistant"))
        #expect(quiet.first { $0.id == "action-toggleSidebar" }?.title == String(localized: "Hide Sidebar"))
        #expect(loud.first { $0.id == "action-toggleSidebar" }?.title == String(localized: "Show Sidebar"))
    }

    @Test func everyActionIsReachableAndRunsItsOwnCase() {
        let context = CommandPaletteContext(
            isPrivate: true,
            historyCount: 5,
            tabCount: 3,
            hasActiveTab: true,
            canGoBack: true,
            canGoForward: true,
            isLoading: true,
            isZoomed: true,
            isAwayFromPin: true,
            canReopenClosedTab: true,
            canSplit: true,
            isSplit: true,
            canSwapPanes: true,
            hasSplitAxis: true,
            canShowLyrics: true,
            canCheckForUpdates: true
        )
        var performed: [CommandPaletteAction] = []
        let commands = CommandPaletteCatalog.commands(context: context) { performed.append($0) }

        #expect(Set(commands.map(\.id)).count == commands.count)
        #expect(commands.count == CommandPaletteAction.allCases.count - 1)

        for command in commands {
            command.run()
        }
        #expect(performed.count == commands.count)
        #expect(!performed.contains(.privateBrowsing))
        #expect(performed.contains(.leavePrivateBrowsing))
    }

    @Test func theGroupedListKeepsTheCatalogOrder() {
        let commands = CommandPaletteCatalog.commands(context: fixtureContext(), perform: { _ in })
        let sections = CommandPaletteCatalog.groupedSections(commands)

        #expect(sections.map(\.id).prefix(2) == ["actions-tabs", "actions-page"])
        #expect(sections.flatMap(\.items).count == commands.count)
        #expect(sections.first?.items.first?.shortcut == "⌘T")
    }

    private func section(_ id: String, count: Int) -> OmniboxSection {
        OmniboxSection(id: id, title: id, items: items(count))
    }

    private func items(_ count: Int) -> [OmniboxItem] {
        (0..<count).map { index in
            OmniboxItem(id: "\(index)", kind: .action, title: "Row \(index)") {}
        }
    }

    private func fixtureCommand() -> CommandPaletteCommand {
        CommandPaletteCommand(
            id: "action-organizeTabs",
            group: .tabs,
            title: "Organize Tabs",
            symbol: "folder",
            aliases: ["tidy", "group"],
            run: {}
        )
    }

    private func fixtureContext() -> CommandPaletteContext {
        CommandPaletteContext(historyCount: 12, tabCount: 4, hasActiveTab: true)
    }
}
