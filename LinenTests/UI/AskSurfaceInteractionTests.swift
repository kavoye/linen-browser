// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AskSurfaceInteractionTests {
    @Test func anUnconfiguredAgentHasAHumanReadableName() {
        #expect(AppCoordinator.displayAgentName(for: "none") == String(localized: "Assistant"))
        #expect(AppCoordinator.displayAgentName(for: "Claude") == "Claude")
    }

    @Test func returnUsesTheSelectedResultBeforeInterpretingTheText() {
        var state = AskSurfaceInteraction()
        state.text = "weather tomorrow"
        state.selection = 2

        #expect(state.submission(resultCount: 4, agentOnly: false) == .result(2))
    }

    @Test func returnRoutesQuestionsLinksAndExplicitAsks() {
        var state = AskSurfaceInteraction()
        state.text = "weather tomorrow"
        #expect(state.submission(resultCount: 0, agentOnly: false) == .navigate("weather tomorrow"))
        #expect(state.submission(resultCount: 0, agentOnly: true) == .ask("weather tomorrow"))

        state.text = "example.com"
        #expect(state.submission(resultCount: 0, agentOnly: true) == .navigate("example.com"))

        state.text = "  @  compare these pages  "
        #expect(state.submission(resultCount: 0, agentOnly: false) == .ask("compare these pages"))
    }

    @Test func anAttachedTabSendsTheQuestionToTheAssistant() {
        var state = AskSurfaceInteraction()
        state.text = "check this price"
        #expect(state.submission(resultCount: 0, agentOnly: false, hasMentions: true) == .ask("check this price"))

        state.text = "example.com"
        #expect(state.submission(resultCount: 0, agentOnly: false, hasMentions: true) == .ask("example.com"))
    }

    @Test func commandReturnAlwaysAsksAndDropsTheAtPrefix() {
        var state = AskSurfaceInteraction()
        state.text = "example.com"
        #expect(state.commandSubmission() == .ask("example.com"))

        state.text = " @ summarize this "
        #expect(state.commandSubmission() == .ask("summarize this"))

        state.text = " @  "
        #expect(state.commandSubmission() == .none)
    }

    @Test func arrowSelectionWrapsAndAnEmptyListResetsIt() {
        var state = AskSurfaceInteraction(text: "query", selection: 0)
        state.moveSelection(by: -1, resultCount: 4)
        #expect(state.selection == 3)
        state.moveSelection(by: 1, resultCount: 4)
        #expect(state.selection == 0)
        state.moveSelection(by: 9, resultCount: 4)
        #expect(state.selection == 1)

        state.moveSelection(by: 1, resultCount: 0)
        #expect(state.selection == 0)
    }

    @Test func commandArrowJumpsBetweenNonemptySections() {
        var state = AskSurfaceInteraction(text: "query", selection: 0)
        let counts = [1, 0, 3, 2]

        state.moveSection(by: 1, itemCounts: counts)
        #expect(state.selection == 1)
        state.moveSection(by: 1, itemCounts: counts)
        #expect(state.selection == 4)
        state.moveSection(by: 1, itemCounts: counts)
        #expect(state.selection == 0)
        state.moveSection(by: -1, itemCounts: counts)
        #expect(state.selection == 4)
    }

    @Test func finishingAndCancellingRespectPlacementSemantics() {
        var state = AskSurfaceInteraction(text: "draft", selection: 4)
        state.cancel(mirrorsPageURL: false, currentURL: "https://example.com")
        #expect(state.text == "draft")
        #expect(state.selection == 0)

        state.selection = 3
        state.cancel(mirrorsPageURL: true, currentURL: "https://example.com")
        #expect(state.text == "https://example.com")
        #expect(state.selection == 0)

        state.finish(restingText: "")
        #expect(state.text.isEmpty)
    }

    @Test func restingContentUsesAStablePrecedenceAndAccessibleValue() {
        let listening = AskRestingContent.resolve(
            isListening: true,
            transcript: "open the first result",
            agentMessage: "Done",
            mirrorsPageURL: true,
            isFocused: false,
            typedText: "",
            notice: "Saved",
            status: "Waiting",
            placeholder: "Search",
            currentURL: "https://www.example.com/path"
        )
        #expect(listening == .transcript("open the first result"))
        #expect(listening?.accessibilityValue(fallback: "") == "open the first result")

        let address = AskRestingContent.resolve(
            isListening: false,
            transcript: "",
            agentMessage: nil,
            mirrorsPageURL: true,
            isFocused: false,
            typedText: "",
            notice: nil,
            status: nil,
            placeholder: "Search",
            currentURL: "https://www.example.com/path"
        )
        #expect(address == .address("example.com"))
        #expect(address?.accessibilityValue(fallback: "https://www.example.com/path") == "https://www.example.com/path")
    }

    @Test func normalResultsHaveAStableOrderAndBoundedGroups() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let history = HistoryStore(database: .temporary())
            for index in 0..<8 {
                history.record(url: "https://example.com/\(index)", title: "Example \(index)")
            }
            let tab = BrowserTab()
            tab.title = "Example tab"
            tab.urlString = "https://example.com/open"

            let sections = AskSurfaceResults.sections(
                placement: .startPage,
                query: "example",
                isFocused: true,
                isListening: false,
                currentURL: "",
                agentOnly: false,
                agentName: "Assistant",
                history: history,
                tabs: [tab],
                phrases: (0..<12).map { "example \($0)" },
                open: { _ in },
                switchTo: { _ in },
                ask: { _ in }
            )

            #expect(sections.map(\.id) == ["top", "history", "tabs", "suggestions", "ask"])
            #expect(sections.first { $0.id == "history" }?.items.count == 2)
            #expect(sections.first { $0.id == "tabs" }?.items.count == 1)
            #expect(sections.first { $0.id == "suggestions" }?.items.count == 6)
        }
    }

    @Test func agentOnlyResultsPutAskFirstForProseAndNeverShowCompletions() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let sections = AskSurfaceResults.sections(
                placement: .startPage,
                query: "compare these pages",
                isFocused: true,
                isListening: false,
                currentURL: "",
                agentOnly: true,
                agentName: "Assistant",
                history: HistoryStore(database: .temporary()),
                tabs: [],
                phrases: ["compare these pages online"],
                open: { _ in },
                switchTo: { _ in },
                ask: { _ in }
            )

            #expect(sections.first?.id == "ask")
            #expect(!sections.contains { $0.id == "suggestions" })
        }
    }
    @Test func anAttachedTabLeavesOnlyTheAskResult() {
        Omnibox.$agentOnlyForTesting.withValue(false) {
            let history = HistoryStore(database: .temporary())
            history.record(url: "https://example.com/desk", title: "Walnut desk")
            let tab = BrowserTab()
            tab.title = "Walnut desk"
            tab.urlString = "https://example.com/desk"

            let sections = AskSurfaceResults.sections(
                placement: .startPage,
                query: "which is cheaper",
                isFocused: true,
                isListening: false,
                currentURL: "",
                agentOnly: false,
                agentName: "Assistant",
                history: history,
                tabs: [tab],
                mentions: [MentionChip(id: tab.id, title: tab.title)],
                phrases: ["which is cheaper online"],
                open: { _ in },
                switchTo: { _ in },
                ask: { _ in }
            )

            #expect(sections.map(\.id) == ["ask"])
        }
    }

    @Test func markersResolveToTitlesAndSurviveDeletion() {
        let first = MentionChip(id: UUID(), title: "Nike Air Max")
        let second = MentionChip(id: UUID(), title: "Adidas Samba")
        let text = "compare \(MentionText.marker) with \(MentionText.marker)"

        #expect(MentionText.count(in: text) == 2)
        #expect(
            MentionText.resolved(text, chips: [first, second])
                == "compare @Nike Air Max with @Adidas Samba"
        )
        #expect(MentionText.stripped(text) == "compare  with ")
        #expect(
            MentionText.removingMarker(at: 0, from: text)
                == "compare  with \(MentionText.marker)"
        )
        #expect(MentionText.appending(to: "which is cheaper @ni") == "which is cheaper \(MentionText.marker) ")
    }

    /// The word being typed offers tabs whenever it opens with “@”, wherever
    /// it sits. Requiring something before the “@” meant typing it first showed
    /// nothing, and typing a space and then “@” showed the list.
    @Test func anAtTokenComposesAMentionWhereverItSits() {
        #expect(AskSurfaceInteraction.mentionFragment(in: "which is cheaper @ni") == "ni")
        #expect(AskSurfaceInteraction.mentionFragment(in: "compare @") == "")
        #expect(AskSurfaceInteraction.mentionFragment(in: "@ni") == "ni")
        #expect(AskSurfaceInteraction.mentionFragment(in: "@") == "")

        // The token has been left behind, so it no longer offers anything.
        #expect(AskSurfaceInteraction.mentionFragment(in: "@ask something") == nil)
        #expect(AskSurfaceInteraction.mentionFragment(in: "which is cheaper @ni ") == nil)
        #expect(AskSurfaceInteraction.mentionFragment(in: "plain question") == nil)
    }

    /// Asking leads only while the “@” is the whole query. Reaching for a tab
    /// part way through a question is not an attempt to ask something new.
    @Test func onlyAnOpeningAtStillOffersToAsk() {
        #expect(AskSurfaceInteraction.mentionOpensTheQuery("@"))
        #expect(AskSurfaceInteraction.mentionOpensTheQuery("@ni"))

        #expect(!AskSurfaceInteraction.mentionOpensTheQuery("@qweqwe qweqwe @"))
        #expect(!AskSurfaceInteraction.mentionOpensTheQuery("which is cheaper @ni"))
        #expect(!AskSurfaceInteraction.mentionOpensTheQuery("plain question"))
        #expect(!AskSurfaceInteraction.mentionOpensTheQuery("@ask something"))
    }

    @Test func removingTheFragmentLeavesTheQuestion() {
        #expect(
            AskSurfaceInteraction.removingMentionFragment(from: "which is cheaper @ni")
                == "which is cheaper "
        )
        #expect(
            AskSurfaceInteraction.removingMentionFragment(from: "no mention here")
                == "no mention here"
        )
    }
}
