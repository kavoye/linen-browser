// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class AskSurfaceModel {
    let placement: AskSurface.Placement
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let suggestions = SearchSuggestions()

    var interaction = AskSurfaceInteraction() {
        didSet {
            if oldValue.text != interaction.text {
                suggestions.update(for: MentionText.stripped(interaction.text))
            }
        }
    }
    private(set) var isFocused = false
    private(set) var mentionedTabIDs: [UUID] = []
    private(set) var selectAllToken = 0

    init(placement: AskSurface.Placement, browser: BrowserModel, coordinator: AppCoordinator) {
        self.placement = placement
        self.browser = browser
        self.coordinator = coordinator
    }

    var activeTabID: UUID? {
        browser.activeTab?.id
    }
    var activeSpaceID: UUID? {
        browser.activeSpaceID
    }
    var currentURL: String {
        browser.activeTab?.urlString ?? ""
    }
    var isListening: Bool {
        coordinator.state == .listening
    }
    var agentOnly: Bool {
        Omnibox.isAgentOnly
    }
    var placeholder: String {
        agentOnly ? Omnibox.agentOnlyPlaceholder : placement.placeholder
    }
    var restingText: String {
        placement.mirrorsPageURL ? currentURL : ""
    }
    var security: PageSecurity {
        browser.activeTab?.security ?? .none
    }
    var isPrivate: Bool {
        browser.activeTab?.isPrivate ?? false
    }

    var agentMessage: String? {
        coordinator.agentReply.message(inSpace: activeSpaceID)
    }

    var restingContent: AskRestingContent? {
        AskRestingContent.resolve(
            isListening: isListening,
            transcript: coordinator.liveTranscript,
            agentMessage: agentMessage,
            mirrorsPageURL: placement.mirrorsPageURL,
            isFocused: isFocused,
            typedText: interaction.trimmedText,
            notice: coordinator.notice,
            status: coordinator.statusMessage,
            placeholder: placeholder,
            currentURL: currentURL
        )
    }

    var accessibilityValue: String {
        restingContent?.accessibilityValue(fallback: interaction.text) ?? interaction.text
    }

    var activity: AskSurfaceActivity {
        guard let activeSpaceID,
              coordinator.agentReply.showsInChrome(inSpace: activeSpaceID)
        else { return .none }
        let traces = coordinator.conversationLog.traces(forTab: activeSpaceID)
        guard let last = traces.last else { return .none }
        let isRunning = last.state == .running
        let isThinking = isRunning
            && (last.steps.isEmpty || last.steps.last?.state == .running)
        return AskSurfaceActivity(count: traces.count, isRunning: isRunning, isThinking: isThinking)
    }

    var mentionedTabs: [BrowserTab] {
        mentionedTabIDs.compactMap { id in
            browser.tabs.first { $0.id == id }
        }
    }

    var mentionChips: [MentionChip] {
        mentionedTabs.map { tab in
            MentionChip(id: tab.id, title: tab.title, host: URL(string: tab.urlString)?.displayHost)
        }
    }

    var contextPages: [AskContextPage] {
        AskContext.pages(browser: browser, mentionedTabIDs: mentionedTabIDs)
    }

    func resultSections() -> [OmniboxSection] {
        AskSurfaceResults.sections(
            placement: placement,
            query: interaction.text,
            isFocused: isFocused,
            isListening: isListening,
            currentURL: currentURL,
            agentOnly: agentOnly,
            agentName: coordinator.agentDisplayName,
            history: browser.history,
            tabs: browser.tabs,
            mentions: mentionChips,
            activeTabID: activeTabID,
            phrases: suggestions.phrases,
            open: { [weak self] in self?.open($0) },
            switchTo: { [weak self] in self?.switchTo($0) },
            mention: { [weak self] in self?.mention($0) },
            ask: { [weak self] in self?.ask($0) }
        )
    }

    func mention(_ tab: BrowserTab) {
        guard !mentionedTabIDs.contains(tab.id) else { return }
        mentionedTabIDs.append(tab.id)
        interaction.text = MentionText.appending(to: interaction.text)
    }

    func removeMention(_ tabID: UUID) {
        guard let index = mentionedTabIDs.firstIndex(of: tabID) else { return }
        mentionedTabIDs.remove(at: index)
        interaction.text = MentionText.removingMarker(at: index, from: interaction.text)
    }

    func mentionsDidChange(_ ids: [UUID]) {
        guard mentionedTabIDs != ids else { return }
        mentionedTabIDs = ids
    }

    func prepare() {
        interaction.text = restingText
    }

    func currentURLDidChange(_ url: String) {
        if !isFocused, placement.mirrorsPageURL {
            interaction.text = url
        }
    }

    func activeTabDidChange() {
        interaction.text = restingText
        mentionedTabIDs = []
        setFocused(false)
    }

    func fieldFocusDidChange(_ focused: Bool) {
        setFocused(focused)
    }

    func focusFromAddressCommand() {
        if placement.mirrorsPageURL {
            interaction.text = currentURL
        }
        selectAllToken += 1
        setFocused(true)
    }

    func replaceTextAndFocus(_ text: String) {
        interaction.text = text
        setFocused(true)
    }

    func focusForEditing() {
        if !coordinator.agentReply.isStreaming {
            coordinator.agentReply.clear()
        }
        if placement.mirrorsPageURL, !isFocused {
            selectAllToken += 1
        }
        setFocused(true)
    }

    func submit(in sections: [OmniboxSection]) {
        switch interaction.submission(
            resultCount: sections.flattened.count,
            agentOnly: agentOnly,
            hasMentions: !mentionedTabIDs.isEmpty
        ) {
        case .none:
            return
        case .result(let index):
            run(at: index, in: sections)
        case .ask(let prompt):
            ask(prompt)
        case .navigate(let input):
            if pendingQuestion == nil {
                navigate(input)
            } else {
                answer(input)
            }
        }
    }

    func askWhateverIsTyped() {
        guard case .ask(let prompt) = interaction.commandSubmission() else { return }
        ask(prompt)
    }

    func run(at index: Int, in sections: [OmniboxSection]) {
        let items = sections.flattened
        guard items.indices.contains(index) else { return }
        items[index].run()
    }

    func moveSelection(by delta: Int, in sections: [OmniboxSection]) {
        interaction.moveSelection(by: delta, resultCount: sections.flattened.count)
    }

    func moveSection(by delta: Int, in sections: [OmniboxSection]) {
        interaction.moveSection(by: delta, itemCounts: sections.map(\.items.count))
    }

    func finishEditing() {
        interaction.finish(restingText: restingText)
        setFocused(false)
    }

    func cancelEditing() {
        interaction.cancel(
            mirrorsPageURL: placement.mirrorsPageURL,
            currentURL: currentURL
        )
        mentionedTabIDs = []
        setFocused(false)
    }

    func open(_ url: URL) {
        browser.ensureActiveTab().load(url)
        finishEditing()
    }

    func navigate(_ input: String) {
        browser.handleAddressInput(input)
        finishEditing()
    }

    func switchTo(_ tab: BrowserTab) {
        finishEditing()
        coordinator.openTab(tab)
    }

    var pendingQuestion: AgentQuestionModel.Ask? {
        coordinator.agentQuestions.ask(inSpace: activeSpaceID)
    }

    func answer(_ text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        interaction.text = ""
        finishEditing()
        coordinator.agentQuestions.answer(answer)
    }

    private func ask(_ prompt: String) {
        let prompt = MentionText.resolved(prompt, chips: mentionChips)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if pendingQuestion != nil {
            answer(prompt)
            return
        }
        let mentions = mentionedTabIDs
        mentionedTabIDs = []
        finishEditing()
        Task { await coordinator.handleTypedUtterance(prompt, mentionedTabIDs: mentions) }
    }

    private func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        if !focused {
            suggestions.clear()
        }
    }
}
