// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class AskSurfaceModel {
    let placement: AskSurface.Placement
    private(set) var browser: BrowserModel
    let coordinator: AppCoordinator
    let suggestions = SearchSuggestions()

    var interaction = AskSurfaceInteraction() {
        didSet {
            if oldValue.text != interaction.text, !isPreviewingSelection {
                suggestionPreview.clear()
                if searchSite == nil {
                    suggestions.update(for: MentionText.stripped(interaction.text), settings: browser.context.settings)
                } else {
                    suggestions.clear()
                }
            }
        }
    }
    private(set) var isFocused = false
    private(set) var mentionedTabIDs: [UUID] = []
    private(set) var searchSite: SearchEngine?
    private(set) var selectAllToken = 0
    private var isPreviewingSelection = false
    private var suggestionPreview = OmniboxSuggestionPreview()

    var resultQuery: String {
        suggestionPreview.query ?? interaction.text
    }

    init(placement: AskSurface.Placement, browser: BrowserModel, coordinator: AppCoordinator) {
        self.placement = placement
        self.browser = browser
        self.coordinator = coordinator
    }

    var activeTabID: UUID? {
        browser.activeTab?.id
    }
    var activeAnchorID: UUID? {
        browser.activeAnchorID
    }
    var currentURL: String {
        browser.activeTab?.urlString ?? ""
    }
    var isListening: Bool {
        coordinator.state == .listening
    }
    var agentOnly: Bool {
        Omnibox.isAgentOnly(settings: browser.context.settings)
    }
    var placeholder: String {
        if let searchSite {
            return String(localized: "Search \(searchSite.name)")
        }
        return agentOnly ? Omnibox.agentOnlyPlaceholder : placement.placeholder
    }

    var suggestedSite: SearchEngine? {
        guard isFocused, searchSite == nil, mentionedTabIDs.isEmpty,
              !placement.mirrorsPageURL || interaction.text != currentURL
        else { return nil }
        return SiteSearch.match(interaction.text, customEngine: browser.context.settings.searchEngine)
    }

    @discardableResult
    func activateSiteSearch() -> Bool {
        guard let site = suggestedSite else { return false }
        searchSite = site
        suggestionPreview.clear()
        suggestions.clear()
        interaction.text = ""
        interaction.selection = 0
        return true
    }

    @discardableResult
    func removeSearchSite() -> Bool {
        guard searchSite != nil else { return false }
        searchSite = nil
        suggestionPreview.clear()
        interaction.selection = 0
        return true
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
        coordinator.agentReply.message(inAnchor: activeAnchorID)
    }

    var restingContent: AskRestingContent? {
        AskRestingContent.resolve(
            isListening: isListening,
            transcript: coordinator.liveTranscript,
            agentMessage: agentMessage,
            mirrorsPageURL: placement.mirrorsPageURL,
            isFocused: isFocused,
            typedText: interaction.trimmedText,
            notice: coordinator.notice.text,
            noticeSymbol: coordinator.notice.symbol,
            status: coordinator.statusMessage,
            placeholder: placeholder,
            currentURL: currentURL,
            showsFullAddress: browser.context.settings.showsFullAddress
        )
    }

    var accessibilityValue: String {
        restingContent?.accessibilityValue(fallback: interaction.text) ?? interaction.text
    }

    var activity: AskSurfaceActivity {
        guard let activeAnchorID,
              coordinator.agentReply.showsInChrome(inAnchor: activeAnchorID)
        else { return .none }
        let traces = coordinator.conversationLog.traces(forTab: activeAnchorID)
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
        if isFocused, !isListening, let sections = suggestionPreview.sections {
            return sections
        }
        if let searchSite {
            let query = interaction.trimmedText
            guard isFocused, !query.isEmpty, let url = searchSite.searchURL(for: query) else { return [] }
            let item = OmniboxItem(
                id: "site-search-\(searchSite.id)",
                kind: .search,
                title: query,
                detail: String(localized: "Search \(searchSite.name)"),
                iconHost: searchSite.host
            ) { [weak self] in
                self?.open(url)
            }
            return [OmniboxSection(id: "site-search", title: "", items: [item])]
        }
        return AskSurfaceResults.sections(
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
            settings: browser.context.settings,
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

    func browserDidChange(_ browser: BrowserModel) {
        guard browser !== self.browser else { return }
        self.browser = browser
        activeTabDidChange()
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
        if searchSite != nil {
            run(at: interaction.selection, in: sections)
            return
        }
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
        if searchSite != nil {
            submit(in: resultSections())
            return
        }
        guard case .ask(let prompt) = interaction.commandSubmission() else { return }
        ask(prompt)
    }

    func run(at index: Int, in sections: [OmniboxSection]) {
        let items = sections.flattened
        guard items.indices.contains(index) else { return }
        items[index].run()
    }

    func remove(at index: Int, in sections: [OmniboxSection]) {
        let items = sections.flattened
        guard items.indices.contains(index), let remove = items[index].remove else { return }
        remove()
        if let typed = suggestionPreview.query {
            interaction.text = typed
        }
        interaction.selection = min(index, max(resultSections().flattened.count - 1, 0))
    }

    func moveSelection(by delta: Int, in sections: [OmniboxSection]) {
        interaction.moveSelection(by: delta, resultCount: sections.flattened.count)
        selectSuggestion(at: interaction.selection, in: sections)
    }

    func moveSection(by delta: Int, in sections: [OmniboxSection]) {
        interaction.moveSection(by: delta, itemCounts: sections.map(\.items.count))
        selectSuggestion(at: interaction.selection, in: sections)
    }

    func selectSuggestion(at index: Int, in sections: [OmniboxSection]) {
        guard let text = suggestionPreview.select(at: index, in: sections, query: interaction.text) else { return }
        isPreviewingSelection = true
        defer { isPreviewingSelection = false }
        interaction.text = text
        interaction.selection = index
    }

    func hoverSuggestion(at index: Int, in sections: [OmniboxSection]) {
        guard sections.flattened.indices.contains(index) else { return }
        interaction.selection = index
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
        coordinator.pendingAgentQuestion(inChrome: true)
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
            searchSite = nil
            suggestionPreview.clear()
            suggestions.clear()
        }
    }
}
