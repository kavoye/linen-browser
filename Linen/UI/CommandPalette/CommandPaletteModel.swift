// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import WebKit

struct CommandPaletteInteraction: Equatable {
    var query = "" {
        didSet {
            if query != oldValue {
                selection = 0
            }
        }
    }
    var selection = 0

    mutating func moveSelection(by delta: Int, resultCount: Int) {
        selection = OmniboxSelection.moved(from: selection, by: delta, resultCount: resultCount)
    }

    mutating func moveSection(by delta: Int, itemCounts: [Int]) {
        selection = OmniboxSelection.movedBySection(from: selection, by: delta, itemCounts: itemCounts)
    }

    mutating func clampSelection(to resultCount: Int) {
        guard resultCount > 0 else {
            selection = 0
            return
        }
        selection = min(max(selection, 0), resultCount - 1)
    }
}

struct CommandPaletteLayout: Equatable {
    static let fieldHeight: CGFloat = 62
    static let margin: CGFloat = 40

    let containerSize: CGSize

    var maxListHeight: CGFloat {
        min(420, max(120, containerSize.height - Self.fieldHeight - Self.margin * 2))
    }

    var topInset: CGFloat {
        max(Self.margin, (containerSize.height - Self.fieldHeight - maxListHeight) / 2)
    }

    var panelWidth: CGFloat {
        let preferred = min(max(containerSize.width * 0.5, 480), 680)
        return min(preferred, max(containerSize.width - Self.margin * 2, 0))
    }
}

enum CommandPaletteShortcutPolicy {
    static let arrowKeys: Set<String> = Set(
        [NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey]
            .compactMap { UnicodeScalar($0).map(String.init) }
    )

    static let returnKeys: Set<String> = ["\r", "\u{3}"]

    static func opensInNewTab(modifiers: NSEvent.ModifierFlags, key: String) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask) == .shift && returnKeys.contains(key)
    }

    static func shouldDismiss(modifiers: NSEvent.ModifierFlags, key: String) -> Bool {
        let modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let editingKeys: Set<String> = ["a", "c", "v", "x", "z"]
        let normalizedKey = key.lowercased()
        let isTextEditing = modifiers == .command && editingKeys.contains(normalizedKey)
        let isPaletteShortcut = modifiers == .command && normalizedKey == "k"
        let isListNavigation = arrowKeys.contains(key)
        let isRun = returnKeys.contains(key)
        let isCommand = !modifiers.isDisjoint(with: [.command, .control, .option])
        return isCommand && !isTextEditing && !isPaletteShortcut && !isListNavigation && !isRun
    }
}

struct CommandPaletteActions {
    var openCurrent: (URL) -> Void = { _ in }
    var ask: (String) -> Void = { _ in }
    var switchTo: (BrowserTab) -> Void = { _ in }
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
        phrases: [String],
        actions: CommandPaletteActions
    ) -> [OmniboxSection] {
        let commands = CommandPaletteCatalog.commands(context: context, perform: actions.perform)

        if let command = commandQuery(in: query) {
            guard !command.isEmpty else { return CommandPaletteCatalog.groupedSections(commands) }
            return [actionsSection(CommandPaletteCatalog.matching(command, in: commands))].compactMap { $0 }
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return restingSections(history: history, tabs: tabs, commands: commands, actions: actions)
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

        let matched = actionsSection(CommandPaletteCatalog.matching(needle, in: commands))
        let promoted = CommandPaletteCatalog.bestScore(needle, in: commands) >= CommandMatch.strong

        var slots = [
            CommandPaletteBudget.Slot(
                Omnibox.topSection(
                    query: needle,
                    openInNewTab: actions.openNew,
                    open: actions.openCurrent
                ),
                floor: 1,
                quota: 2
            ),
        ]
        if promoted {
            slots.append(CommandPaletteBudget.Slot(matched, floor: 1, quota: 3))
        }
        slots.append(CommandPaletteBudget.Slot(
            askSection(needle, agentName: agentName, ask: actions.ask),
            floor: 1,
            quota: 1
        ))
        slots.append(CommandPaletteBudget.Slot(
            Omnibox.tabsSection(query: needle, tabs: tabs, limit: 4, switchTo: actions.switchTo),
            floor: 2,
            quota: 4
        ))
        slots.append(CommandPaletteBudget.Slot(
            Omnibox.historySection(query: needle, store: history, limit: 5, open: actions.openNew),
            floor: 2,
            quota: 5
        ))
        if !promoted {
            slots.append(CommandPaletteBudget.Slot(matched, floor: 1, quota: 3))
        }
        slots.append(CommandPaletteBudget.Slot(
            Omnibox.phrasesSection(
                query: needle,
                phrases: phrases,
                limit: 3,
                openInNewTab: actions.openNew,
                open: actions.openCurrent
            ),
            floor: 2,
            quota: 3
        ))

        return CommandPaletteBudget.fit(slots, total: CommandPaletteBudget.typing)
    }

    private static func askSection(
        _ prompt: String,
        agentName: String,
        ask: @escaping (String) -> Void
    ) -> OmniboxSection {
        OmniboxSection(
            id: "ask",
            title: String(localized: "Ask \(agentName)"),
            items: [
                OmniboxItem(id: "ask-agent", kind: .ask, title: prompt, shortcut: "⌘↩") {
                    ask(prompt)
                },
            ]
        )
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
        commands: [CommandPaletteCommand],
        actions: CommandPaletteActions
    ) -> [OmniboxSection] {
        let openTabs = tabs.map { tab in
            let host = URL(string: tab.urlString)?.displayHost
            return OmniboxItem(
                id: "tab-\(tab.id)",
                kind: .tab,
                title: tab.title,
                detail: host ?? String(localized: "tab"),
                iconHost: host
            ) {
                actions.switchTo(tab)
            }
        }

        let openURLs = Set(tabs.map(\.urlString))
        let recent = history.entries
            .filter { !openURLs.contains($0.url) }
            .prefix(8)
            .compactMap { entry -> OmniboxItem? in
                guard let url = URL(string: entry.url) else { return nil }
                return OmniboxItem(
                    id: "recent-\(entry.id)",
                    kind: .history,
                    title: entry.title,
                    detail: url.displayAddress ?? entry.url,
                    iconHost: url.displayHost
                ) {
                    actions.openNew(url)
                }
            }

        let slots = [
            CommandPaletteBudget.Slot(
                OmniboxSection(id: "tabs", title: String(localized: "Open Tabs"), items: openTabs),
                floor: 3,
                quota: 5
            ),
            CommandPaletteBudget.Slot(
                actionsSection(
                    CommandPaletteCatalog.suggested(commands),
                    hint: String(localized: "Type > for commands")
                ),
                floor: 3,
                quota: 6
            ),
            CommandPaletteBudget.Slot(
                OmniboxSection(id: "recent", title: String(localized: "Recently Visited"), items: Array(recent)),
                floor: 2,
                quota: 4
            ),
        ]
        return CommandPaletteBudget.fit(slots, total: CommandPaletteBudget.resting)
    }
}

@MainActor
@Observable
final class CommandPaletteModel {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let dismiss: () -> Void
    let suggestions = SearchSuggestions()

    var interaction = CommandPaletteInteraction() {
        didSet {
            guard interaction.query != oldValue.query else { return }
            suggestions.update(for: MentionText.stripped(
                CommandPaletteProjection.suggestionQuery(for: interaction.query)
            ))
            refreshSections()
        }
    }
    private(set) var sections: [OmniboxSection] = []
    private(set) var mentionedTabIDs: [UUID] = []

    init(browser: BrowserModel, coordinator: AppCoordinator, dismiss: @escaping () -> Void) {
        self.browser = browser
        self.coordinator = coordinator
        self.dismiss = dismiss
    }

    var placeholder: String {
        CommandPaletteProjection.placeholder(agentOnly: Omnibox.isAgentOnly)
    }

    func prepare() {
        refreshSections()
    }

    func suggestionsDidChange() {
        refreshSections()
    }

    func moveSelection(by delta: Int) {
        interaction.moveSelection(by: delta, resultCount: sections.flattened.count)
    }

    func moveSection(by delta: Int) {
        interaction.moveSection(by: delta, itemCounts: sections.itemCounts)
    }

    func submit() {
        run(at: interaction.selection)
    }

    func submitInNewTab() {
        runAlternate(at: interaction.selection)
    }

    func askWhateverIsTyped() {
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
        guard CommandPaletteProjection.isAssistantQuery(
            interaction.query,
            hasMentions: !mentionedTabIDs.isEmpty,
            agentOnly: Omnibox.isAgentOnly
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
        sections = CommandPaletteProjection.sections(
            query: interaction.query,
            agentName: coordinator.agentDisplayName,
            context: context,
            history: browser.history,
            tabs: browser.tabs,
            mentions: mentionChips,
            activeTabID: browser.activeTab?.id,
            phrases: suggestions.phrases,
            actions: projectionActions
        )
        interaction.clampSelection(to: sections.flattened.count)
    }

    private var context: CommandPaletteContext {
        let tab = browser.activeTab
        let split = browser.activeSplit
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return CommandPaletteContext(
            isSpeechMuted: coordinator.isSpeechMuted,
            isListening: coordinator.voiceInput.phase == .listening,
            isPrivate: coordinator.profiles.isPrivate,
            historyCount: browser.history.count,
            tabCount: browser.tabs.count,
            hasActiveTab: tab != nil,
            canGoBack: tab?.canGoBack ?? false,
            canGoForward: tab?.canGoForward ?? false,
            isLoading: tab?.isLoading ?? false,
            isZoomed: tab?.isZoomed ?? false,
            isShowingPin: tab?.isShowingPin ?? false,
            isAwayFromPin: tab?.isAwayFromPin ?? false,
            canReopenClosedTab: browser.canReopenClosedTab,
            canSplit: tab != nil && !(split?.isFull ?? false),
            isSplit: coordinator.isSplit,
            canSwapPanes: browser.activeTabID.flatMap { split?.sibling(of: $0) } != nil,
            isStacked: split?.axis == .stacked,
            hasSplitAxis: split?.axis != nil,
            isSidebarVisible: coordinator.sidebar.isVisible,
            isActivityVisible: coordinator.sidePanel.isShowing(.activity),
            isLyricsVisible: coordinator.sidePanel.isShowing(.lyrics),
            canShowLyrics: coordinator.settings.showsLyrics,
            isBrowserVisible: coordinator.browserVisible,
            isFullScreen: window?.styleMask.contains(.fullScreen) ?? false,
            canCheckForUpdates: coordinator.updates.canCheck
        )
    }

    private var projectionActions: CommandPaletteActions {
        CommandPaletteActions(
            openCurrent: { [weak self] url in self?.openCurrent(url) },
            ask: { [weak self] prompt in self?.ask(prompt) },
            switchTo: { [weak self] tab in self?.switchTo(tab) },
            mention: { [weak self] tab in self?.mention(tab) },
            openNew: { [weak self] url in self?.openNew(url) },
            perform: { [weak self] action in self?.perform(action) }
        )
    }

    private func openCurrent(_ url: URL) {
        coordinator.showBrowserPage()
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

    private func openNew(_ url: URL) {
        coordinator.openNewTab(url: url)
        dismiss()
    }

    private func perform(_ action: CommandPaletteAction) {  // swiftlint:disable:this cyclomatic_complexity
        dismiss()
        let tab = browser.activeTab
        switch action {
        case .newTab:
            coordinator.openNewTab()
        case .privateBrowsing:
            coordinator.enterPrivateBrowsing()
        case .leavePrivateBrowsing:
            coordinator.leavePrivateBrowsing()
        case .closeTab:
            browser.closeActiveTab()
        case .reopenTab:
            browser.reopenLastClosedTab()
            coordinator.showBrowserPage()
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
        case .reload:
            tab?.webView.reload()
        case .hardReload:
            tab?.webView.reloadFromOrigin()
        case .stopLoading:
            tab?.webView.stopLoading()
        case .goBack:
            tab?.goBack()
        case .goForward:
            tab?.goForward()
        case .find:
            tab?.find.open()
        case .copyLink:
            coordinator.copyCurrentURL()
        case .printPage:
            coordinator.printActivePage()
        case .zoomIn:
            tab?.zoomIn()
        case .zoomOut:
            tab?.zoomOut()
        case .actualSize:
            tab?.resetZoom()
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
        case .toggleActivity:
            coordinator.toggleAgentInspector()
        case .toggleLyrics:
            coordinator.toggleLyrics()
        case .toggleFullScreen:
            coordinator.toggleFullScreen()
        case .toggleBrowser:
            coordinator.toggleBrowser()
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
        }
    }
}
