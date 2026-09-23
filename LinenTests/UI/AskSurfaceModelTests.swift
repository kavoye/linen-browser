// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The ask-surface model's editing lifecycle: what the field shows at rest,
/// what focus and cancellation restore, and when the suggestion list is
/// cleared. `Omnibox.agentOnlyForTesting` stays pinned so no keystroke can
/// leave the machine as a completion request.
@MainActor
struct AskSurfaceModelTests {
    @Test(arguments: [AskSurface.Placement.toolbar, .startPage])
    func currentPageCanBeSelectedForAThreePageComparison(placement: AskSurface.Placement) throws {
        try Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model(placement: placement)
            let tabs = (0..<3).map { index in
                let tab = model.browser.newTab()
                tab.urlString = "https://shop.example/item/\(index)"
                tab.title = "Item \(index)"
                return tab
            }
            model.browser.activate(tabs[0])
            model.fieldFocusDidChange(true)
            model.interaction.text = "compare @"

            for tab in tabs {
                let item = try #require(model.resultSections().flattened.first { $0.id == "mention-\(tab.id)" })
                item.run()
                #expect(!model.resultSections().flattened.contains { $0.id == "mention-\(tab.id)" })
                model.interaction.text += "@"
            }

            #expect(model.mentionedTabIDs == tabs.map(\.id))
            #expect(model.contextPages.map(\.id) == tabs.map(\.id))
            #expect(MentionText.resolved(model.interaction.text, chips: model.mentionChips)
                == "compare @Item 0 @Item 1 @Item 2 @")
            #expect(model.browser.contextSummary(mentionedTabIDs: model.mentionedTabIDs)?
                .contains("ACTIVE, MENTIONED") == true)
        }
    }

    private func model(placement: AskSurface.Placement = .toolbar) -> AskSurfaceModel {
        let coordinator = AppCoordinator()
        return AskSurfaceModel(
            placement: placement,
            browser: coordinator.browser,
            coordinator: coordinator
        )
    }

    @Test func theToolbarFieldRestsOnThePageAddress() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.browser.newTab()
            model.browser.activeTab?.urlString = "https://example.com/page"
            model.prepare()
            #expect(model.interaction.text == "https://example.com/page")
        }
    }

    @Test func theStartPageFieldRestsEmpty() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model(placement: .startPage)
            model.browser.newTab()
            model.browser.activeTab?.urlString = "https://example.com"
            model.prepare()
            #expect(model.interaction.text.isEmpty)
        }
    }

    @Test func cancellingRestoresThePageAddressAndDropsFocus() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.browser.newTab()
            model.browser.activeTab?.urlString = "https://example.com"
            model.fieldFocusDidChange(true)
            model.interaction.text = "half-typed quer"
            model.cancelEditing()
            #expect(model.interaction.text == "https://example.com")
            #expect(!model.isFocused)
        }
    }

    @Test func switchingTabsResetsTheFieldToTheNewTabsAddress() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.browser.newTab()
            model.fieldFocusDidChange(true)
            model.interaction.text = "typing something"
            model.browser.newTab()
            model.browser.activeTab?.urlString = "https://other.example"
            model.activeTabDidChange()
            #expect(model.interaction.text == "https://other.example")
            #expect(!model.isFocused)
        }
    }

    /// A page navigating underneath the field must not overwrite what the
    /// user is typing; at rest it must.
    @Test func navigationOnlyUpdatesAnUnfocusedField() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.browser.newTab()
            model.currentURLDidChange("https://first.example")
            #expect(model.interaction.text == "https://first.example")

            model.fieldFocusDidChange(true)
            model.interaction.text = "my query"
            model.currentURLDidChange("https://second.example")
            #expect(model.interaction.text == "my query")
        }
    }

    @Test func theAddressCommandFocusesWithTheCurrentAddress() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.browser.newTab()
            model.browser.activeTab?.urlString = "https://example.com"
            model.focusFromAddressCommand()
            #expect(model.isFocused)
            #expect(model.interaction.text == "https://example.com")
        }
    }

    @Test func replacingTextFocusesTheField() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.replaceTextAndFocus("find the walnut desk")
            #expect(model.isFocused)
            #expect(model.interaction.text == "find the walnut desk")
        }
    }

    @Test func runningPastTheEndOfTheResultsDoesNothing() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            let tabsBefore = model.browser.tabs.count
            model.run(at: 5, in: [])
            #expect(model.browser.tabs.count == tabsBefore)
        }
    }

    @Test func browsingSuggestionsPreviewsFullTextWithoutChangingTheResults() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.replaceTextAndFocus("exam")
            var runs = 0
            let sections = [OmniboxSection(id: "preview", title: "", items: [
                OmniboxItem(id: "query", kind: .search, title: "exam") { runs += 1 },
                OmniboxItem(
                    id: "page", kind: .history, title: "Example page",
                    completionText: "https://example.com/full/path?q=value#section"
                ) { runs += 1 },
                OmniboxItem(id: "phrase", kind: .phrase, title: "example search phrase") { runs += 1 },
            ]), ]

            model.moveSelection(by: 1, in: sections)
            #expect(model.interaction.text == "https://example.com/full/path?q=value#section")
            #expect(model.interaction.selection == 1)
            #expect(model.resultQuery == "exam")
            #expect(model.resultSections().flattened.map(\.id) == ["query", "page", "phrase"])

            model.moveSelection(by: 1, in: model.resultSections())
            #expect(model.interaction.text == "example search phrase")
            model.selectSuggestion(at: 0, in: model.resultSections())
            #expect(model.interaction.text == "exam")
            #expect(runs == 0)
        }
    }

    @Test func hoveringAHistoryResultDoesNotReplaceTypedText() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.replaceTextAndFocus("s")
            let sections = [OmniboxSection(id: "history", title: "History", items: [
                OmniboxItem(id: "query", kind: .search, title: "s") {},
                OmniboxItem(
                    id: "page", kind: .history, title: "Some page",
                    completionText: "https://some.example/page"
                ) {},
            ]), ]

            model.hoverSuggestion(at: 1, in: sections)

            #expect(model.interaction.text == "s")
            #expect(model.interaction.selection == 1)
            model.interaction.text += "earch"
            #expect(model.interaction.text == "search")
            #expect(model.resultQuery == "search")
        }
    }

    @Test func typingAfterPreviewStartsANewQueryAndClearsSelection() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            model.replaceTextAndFocus("exam")
            let sections = [OmniboxSection(id: "preview", title: "", items: [
                OmniboxItem(id: "query", kind: .search, title: "exam") {},
                OmniboxItem(id: "phrase", kind: .phrase, title: "example phrase") {},
            ]), ]
            model.selectSuggestion(at: 1, in: sections)
            model.interaction.text += " more"

            #expect(model.resultQuery == "example phrase more")
            #expect(model.interaction.selection == 0)
            #expect(!model.resultSections().contains { $0.id == "preview" })
        }
    }
    @Test func mentioningATabRecordsItAndStripsTheToken() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            let active = model.browser.newTab()
            let other = model.browser.newTab(url: URL(string: "https://shop.example/air-max"))
            other.title = "Nike Air Max"
            model.browser.activate(active)
            model.fieldFocusDidChange(true)
            model.interaction.text = "which is cheaper @ni"

            model.mention(other)

            #expect(model.mentionedTabIDs == [other.id])
            #expect(model.interaction.text == "which is cheaper \(MentionText.marker) ")
            #expect(model.mentionedTabs.map(\.id) == [other.id])
            #expect(model.mentionChips.map(\.title) == ["Nike Air Max"])
            #expect(model.mentionChips.map(\.host) == ["shop.example"])

            model.mention(other)
            #expect(model.mentionedTabIDs == [other.id])

            model.removeMention(other.id)
            #expect(model.mentionedTabIDs.isEmpty)
            #expect(model.interaction.text == "which is cheaper  ")
        }
    }

    @Test func cancellingOrSwitchingTabsDropsComposedMentions() {
        Omnibox.$agentOnlyForTesting.withValue(true) {
            let model = model()
            let active = model.browser.newTab()
            let other = model.browser.newTab()
            model.browser.activate(active)
            model.fieldFocusDidChange(true)
            model.mention(other)
            #expect(!model.mentionedTabIDs.isEmpty)

            model.cancelEditing()
            #expect(model.mentionedTabIDs.isEmpty)

            model.fieldFocusDidChange(true)
            model.mention(other)
            model.activeTabDidChange()
            #expect(model.mentionedTabIDs.isEmpty)
        }
    }
}
