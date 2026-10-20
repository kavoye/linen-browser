// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class CommandPaletteModel {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let dismiss: () -> Void
    let suggestions = SearchSuggestions()
    let gitHubSearch = GitHubPaletteSearch()

    var interaction = CommandPaletteInteraction() {
        didSet {
            guard interaction.query != oldValue.query, !isPreviewingSelection else { return }
            suggestionPreview.clear()
            if isGitHubMode {
                gitHubSearch.update(interaction.query, model: coordinator.github)
            }
            if searchSite == nil, !showsArchive {
                suggestions.update(for: MentionText.stripped(
                    CommandPaletteProjection.suggestionQuery(for: interaction.query)
                ), settings: browser.context.settings)
            } else {
                suggestions.clear()
            }
            refreshSections()
        }
    }
    private(set) var sections: [OmniboxSection] = []
    private(set) var mentionedTabIDs: [UUID] = []
    private(set) var searchSite: SearchEngine?
    private(set) var showsArchive = false
    private var isPreviewingSelection = false
    private var suggestionPreview = OmniboxSuggestionPreview()

    var resultQuery: String {
        suggestionPreview.query ?? interaction.query
    }

    init(
        browser: BrowserModel,
        coordinator: AppCoordinator,
        dismiss: @escaping () -> Void
    ) {
        self.browser = browser
        self.coordinator = coordinator
        self.dismiss = dismiss
        gitHubSearch.onChange = { [weak self] in self?.suggestionsDidChange() }
    }

    private var isGitHubMode: Bool {
        searchSite?.id == "github" && browser.context.settings.showsGitHub && coordinator.github.canPreview
    }

    var placeholder: String {
        if let searchSite {
            return String(localized: "Search \(searchSite.name)")
        }
        if showsArchive {
            return String(localized: "Search archived tabs")
        }
        return CommandPaletteProjection.placeholder(agentOnly: Omnibox.isAgentOnly(settings: browser.context.settings))
    }

    var suggestedSite: SearchEngine? {
        guard searchSite == nil, !showsArchive, mentionedTabIDs.isEmpty else { return nil }
        return SiteSearch.match(interaction.query, customEngine: browser.context.settings.searchEngine)
    }

    var suggestsArchive: Bool {
        searchSite == nil && !showsArchive && mentionedTabIDs.isEmpty && suggestedSite == nil
            && !browser.tabArchive.entries.isEmpty
            && CommandPaletteProjection.opensArchive(interaction.query)
    }

    var scopeHint: String? {
        if let suggestedSite {
            return String(localized: "Search \(suggestedSite.name)")
        }
        return suggestsArchive ? String(localized: "Search archived tabs") : nil
    }

    @discardableResult
    func activateSiteSearch() -> Bool {
        if suggestsArchive {
            showArchive()
            return true
        }
        guard let site = suggestedSite else { return false }
        searchSite = site
        suggestionPreview.clear()
        suggestions.clear()
        interaction.query = ""
        refreshSections()
        return true
    }

    @discardableResult
    func removeSearchSite() -> Bool {
        guard searchSite != nil || showsArchive else { return false }
        gitHubSearch.cancel()
        searchSite = nil
        showsArchive = false
        suggestionPreview.clear()
        interaction.selection = 0
        refreshSections()
        return true
    }

    func prepare() {
        refreshSections()
    }

    func suggestionsDidChange() {
        guard suggestionPreview.sections == nil else { return }
        let selectedID = sections.flattened.indices.contains(interaction.selection)
            ? sections.flattened[interaction.selection].id
            : nil
        refreshSections()
        if let selectedID, let index = sections.flattened.firstIndex(where: { $0.id == selectedID }) {
            interaction.selection = index
        } else {
            interaction.selection = 0
        }
    }

    func moveSelection(by delta: Int) {
        interaction.moveSelection(by: delta, resultCount: sections.flattened.count)
        selectSuggestion(at: interaction.selection)
    }

    func moveSection(by delta: Int) {
        interaction.moveSection(by: delta, itemCounts: sections.itemCounts)
        selectSuggestion(at: interaction.selection)
    }

    func selectSuggestion(at index: Int) {
        guard let text = suggestionPreview.select(at: index, in: sections, query: interaction.query) else { return }
        isPreviewingSelection = true
        defer { isPreviewingSelection = false }
        interaction.query = text
        interaction.selection = index
    }

    func hoverSuggestion(at index: Int) {
        guard sections.flattened.indices.contains(index) else { return }
        interaction.selection = index
    }

    func submit() {
        guard (searchSite == nil && !showsArchive) || !sections.isEmpty else { return }
        run(at: interaction.selection)
    }

    func submitInCurrentTab() {
        guard (searchSite == nil && !showsArchive) || !sections.isEmpty else { return }
        runAlternate(at: interaction.selection)
    }

    func askWhateverIsTyped() {
        if searchSite != nil || showsArchive {
            submit()
            return
        }
        ask(interaction.query)
    }

    func run(at index: Int) {
        let items = sections.flattened
        guard items.indices.contains(index) else {
            dismiss()
            return
        }
        items[index].run()
    }

    func remove(at index: Int) {
        let items = sections.flattened
        guard items.indices.contains(index), let remove = items[index].remove else { return }
        remove()
        refreshAfterRemoval(at: index)
    }

    private func refreshAfterRemoval(at index: Int) {
        if let typed = suggestionPreview.query {
            interaction.query = typed
        } else {
            refreshSections()
        }
        interaction.selection = min(index, max(sections.flattened.count - 1, 0))
    }

    private func close(_ tab: BrowserTab) {
        coordinator.closeAskingIfPinned(tab) { [weak self] in
            guard let self else { return }
            refreshAfterRemoval(at: interaction.selection)
        }
    }

    func runAlternate(at index: Int) {
        let items = sections.flattened
        guard items.indices.contains(index) else {
            dismiss()
            return
        }
        let item = items[index]
        (item.alternate ?? item.run)()
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
        guard searchSite == nil, !showsArchive, CommandPaletteProjection.isAssistantQuery(
            interaction.query,
            hasMentions: !mentionedTabIDs.isEmpty,
            agentOnly: Omnibox.isAgentOnly(settings: browser.context.settings)
        ) else { return [] }
        return AskContext.pages(browser: browser, mentionedTabIDs: mentionedTabIDs)
    }

    func mention(_ tab: BrowserTab) {
        guard !mentionedTabIDs.contains(tab.id) else { return }
        mentionedTabIDs.append(tab.id)
        interaction.query = MentionText.appending(to: interaction.query)
        refreshSections()
    }

    func mentionsDidChange(_ ids: [UUID]) {
        guard mentionedTabIDs != ids else { return }
        mentionedTabIDs = ids
        refreshSections()
    }

    private func refreshSections() {
        guard suggestionPreview.sections == nil else { return }
        if let searchSite {
            let query = interaction.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let webItem = query.isEmpty ? nil : searchSite.searchURL(for: query).map { url in
                OmniboxItem(
                    id: "site-search-\(searchSite.id)",
                    kind: .search,
                    title: query,
                    detail: String(localized: "Search \(searchSite.name)"),
                    iconHost: searchSite.host,
                    alternate: { [weak self] in self?.openCurrent(url) },
                    run: { [weak self] in self?.openNew(url) }
                )
            }
            if isGitHubMode {
                let github = coordinator.github
                sections = GitHubPaletteSections.build(
                    query: query, webItem: webItem,
                    context: GitHubPaletteRoute.repository(of: browser.activeTab?.committedURL),
                    known: github.knownRepositories, mine: github.triage.authored,
                    hits: gitHubSearch.hits, hitsQuery: gitHubSearch.hitsQuery,
                    actions: GitHubPaletteActions(
                        open: { [weak self] url in
                            self?.coordinator.openGitHubLink(url)
                            self?.dismiss()
                        },
                        openCurrent: { [weak self] url in self?.openCurrent(url) },
                        split: { [weak self] url, other in
                            self?.coordinator.openGitHubSplit(url, beside: other)
                            self?.dismiss()
                        }
                    )
                )
            } else if let webItem {
                sections = [OmniboxSection(id: "site-search", title: "", items: [webItem])]
            } else {
                sections = []
            }
            interaction.clampSelection(to: sections.flattened.count)
            return
        }
        if showsArchive {
            let archive = browser.tabArchive
            let section = Omnibox.archivedSection(
                query: interaction.query,
                entries: archive.entries,
                excluding: Set(browser.tabs.map(\.urlString)),
                restore: { [weak self] entry in self?.restore(entry) },
                remove: { archive.remove($0) }
            )
            sections = section.map { [$0] } ?? []
            interaction.clampSelection(to: sections.flattened.count)
            return
        }
        sections = CommandPaletteProjection.sections(
            query: interaction.query,
            agentName: coordinator.agentDisplayName,
            context: context,
            history: browser.history,
            tabs: browser.tabs,
            mentions: mentionChips,
            activeTabID: browser.activeTab?.id,
            recentTabIDs: browser.recentlyActive,
            phrases: suggestions.phrases,
            settings: browser.context.settings,
            actions: projectionActions
        )
        interaction.clampSelection(to: sections.flattened.count)
    }

    private var context: CommandPaletteContext {
        let tab = browser.activeTab
        let page = coordinator.pageCommandTab
        let split = browser.activeSplit
        let window = coordinator.nativeWindow
        return CommandPaletteContext(
            isSpeechMuted: coordinator.isSpeechMuted,
            isListening: coordinator.voiceInput.phase == .listening,
            historyCount: browser.history.count,
            tabCount: browser.tabs.count,
            hasActiveTab: tab != nil,
            canReload: page?.canReload ?? false,
            canGoBack: page?.canGoBack ?? false,
            canGoForward: page?.canGoForward ?? false,
            isLoading: page?.isLoading ?? false,
            isZoomed: page?.isZoomed ?? false,
            isTranslated: page?.translation.isActive ?? false,
            canTranslate: page?.canToggleTranslation ?? false,
            canInspect: page.map { browser.context.settings.webInspectorEnabled || $0.usesDeveloperMode } ?? false,
            canScreenshot: page?.isMaterialised ?? false,
            isShowingPin: tab?.isShowingPin ?? false,
            isAwayFromPin: tab?.isAwayFromPin ?? false,
            canReopenClosedTab: browser.canReopenClosedTab,
            canReopenClosedWindow: coordinator.application?.canReopenWindow == true,
            archivedCount: browser.tabArchive.entries.count,
            canSplit: tab != nil && !(split?.isFull ?? false),
            isSplit: coordinator.isSplit,
            canSwapPanes: browser.activeTabID.flatMap { split?.sibling(of: $0) } != nil,
            isStacked: split?.axis == .stacked,
            hasSplitAxis: split?.axis != nil,
            isSidebarVisible: coordinator.sidebar.isVisible,
            isSidePanelVisible: coordinator.sidePanel.isVisible,
            isMinimal: coordinator.settings.isMinimal,
            isBarOnTop: coordinator.settings.minimalBarEdge == .top,
            isFullScreen: window?.styleMask.contains(.fullScreen) ?? false,
            canCheckForUpdates: coordinator.updates.canCheck
        )
    }

    private var projectionActions: CommandPaletteActions {
        CommandPaletteActions(
            openCurrent: { [weak self] url in self?.openCurrent(url) },
            ask: { [weak self] prompt in self?.ask(prompt) },
            switchTo: { [weak self] tab in self?.switchTo(tab) },
            close: { [weak self] tab in self?.close(tab) },
            mention: { [weak self] tab in self?.mention(tab) },
            openNew: { [weak self] url in self?.openNew(url) },
            perform: { [weak self] action in self?.perform(action) }
        )
    }

    private func openCurrent(_ url: URL) {
        browser.ensureActiveTab().load(url)
        dismiss()
    }

    private func ask(_ prompt: String) {
        let prompt = MentionText.resolved(prompt, chips: mentionChips)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let mentions = mentionedTabIDs
        mentionedTabIDs = []
        dismiss()
        Task { await coordinator.handleTypedUtterance(prompt, mentionedTabIDs: mentions) }
    }

    private func switchTo(_ tab: BrowserTab) {
        coordinator.openTab(tab)
        dismiss()
    }

    private func restore(_ entry: TabArchive.Entry) {
        browser.restore(entry)
        dismiss()
    }

    private func openNew(_ url: URL) {
        coordinator.openNewTab(url: url)
        dismiss()
    }

    private func showArchive() {
        showsArchive = true
        mentionedTabIDs = []
        suggestionPreview.clear()
        suggestions.clear()
        interaction.query = ""
        refreshSections()
    }

    private func perform(_ action: CommandPaletteAction) {  // swiftlint:disable:this cyclomatic_complexity
        if action == .showArchivedTabs {
            showArchive()
            return
        }
        if action == .openLocation, coordinator.settings.isMinimal {
            interaction.query = coordinator.locationSeed ?? ""
            return
        }
        dismiss()
        let tab = browser.activeTab
        let page = coordinator.pageCommandTab
        switch action {
        case .newTab:
            coordinator.requestNewTab()
        case .newWindow:
            coordinator.requestNewWindow()
        case .openStartPage:
            coordinator.openNewTab()
        case .openLocation:
            coordinator.focusAddressBar()
        case .privateBrowsing:
            coordinator.requestNewWindow(isPrivate: true)
        case .closeTab:
            coordinator.closeActiveTabAskingIfPinned()
        case .reopenTab:
            browser.reopenLastClosedTab()
        case .reopenWindow:
            coordinator.application?.reopenLastClosedWindow()
        case .showArchivedTabs:
            break
        case .duplicateTab:
            if let tab {
                browser.duplicate(tab)
            }
        case .togglePin:
            coordinator.togglePin()
        case .returnToPin:
            if let tab {
                browser.returnToPin(tab)
            }
        case .organizeTabs:
            coordinator.organizeTabs()
        case .nextTab:
            browser.cycleTab(forward: true)
        case .previousTab:
            browser.cycleTab(forward: false)
        case .lastTab:
            browser.activateLastTab()
        case .showTab1, .showTab2, .showTab3, .showTab4, .showTab5, .showTab6, .showTab7, .showTab8:
            if let index = CommandPaletteAction.indexedTabs.firstIndex(of: action) {
                browser.activateTab(at: index)
            }
        case .reload, .hardReload, .stopLoading, .goBack, .goForward, .find, .findNext, .findPrevious,
             .zoomIn, .zoomOut, .actualSize, .showWebInspector:
            if let page {
                perform(action, on: page)
            }
        case .copyLink:
            coordinator.copyCurrentURL()
        case .copyScreenshot:
            if let page {
                coordinator.copyScreenshot(of: page)
            }
        case .printPage:
            coordinator.printActivePage()
        case .translatePage:
            if let page {
                coordinator.toggleTranslation(page)
            }
        case .splitRight:
            coordinator.splitActiveTab(axis: .sideBySide)
        case .splitDown:
            coordinator.splitActiveTab(axis: .stacked)
        case .otherPane:
            coordinator.focusOtherPane()
        case .swapPanes:
            coordinator.swapSplitPanes()
        case .toggleSplitAxis:
            coordinator.toggleSplitAxis()
        case .exitSplit:
            coordinator.exitSplit()
        case .closeOtherPanes:
            coordinator.closeOtherPanes()
        case .toggleSidebar:
            coordinator.toggleSidebar()
        case .toggleSidePanel:
            coordinator.toggleSidePanel()
        case .toggleMinimal:
            coordinator.toggleMinimal()
        case .moveMinimalBar:
            coordinator.moveMinimalBar()
        case .toggleFullScreen:
            coordinator.toggleFullScreen()
        case .closeWindow:
            coordinator.closeWindow()
        case .minimizeWindow:
            coordinator.nativeWindow?.performMiniaturize(nil)
        case .toggleSpeech:
            coordinator.toggleSpeechMute()
        case .toggleListening:
            coordinator.toggleMicListening()
        case .showHistory:
            coordinator.showHistory()
        case .showDownloads:
            coordinator.showDownloads()
        case .clearHistory:
            coordinator.confirmClearHistory()
        case .settings:
            coordinator.openSettings()
        case .extensions:
            coordinator.openSettings(.extensions)
        case .checkForUpdates:
            coordinator.updates.checkNow()
        case .releaseNotes:
            coordinator.showReleaseNotes()
        case .aboutLinen:
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quitLinen:
            NSApp.terminate(nil)
        }
    }

    private func perform(_ action: CommandPaletteAction, on page: BrowserTab) {
        switch action {
        case .reload:
            page.reload()
        case .hardReload:
            page.webView.reloadFromOrigin()
        case .stopLoading:
            page.stopLoading()
        case .goBack:
            page.goBack()
        case .goForward:
            page.goForward()
        case .find:
            page.find.open()
        case .findNext:
            page.find.findNext(backwards: false)
        case .findPrevious:
            page.find.findNext(backwards: true)
        case .zoomIn:
            page.zoomIn()
        case .zoomOut:
            page.zoomOut()
        case .actualSize:
            page.resetZoom()
        case .showWebInspector:
            page.showWebInspector()
        default:
            break
        }
    }
}
