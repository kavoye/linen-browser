// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct CommandPaletteContext {
    var isSpeechMuted = false
    var isListening = false
    var isPrivate = false
    var historyCount = 0
    var tabCount = 0
    var hasActiveTab = false
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var isZoomed = false
    var isShowingPin = false
    var isAwayFromPin = false
    var canReopenClosedTab = false
    var canSplit = false
    var isSplit = false
    var canSwapPanes = false
    var isStacked = false
    var hasSplitAxis = false
    var isSidebarVisible = true
    var isActivityVisible = false
    var isBrowserVisible = true
    var isFullScreen = false
    var canCheckForUpdates = false
}

enum CommandPaletteAction: String, CaseIterable {
    case newTab
    case privateBrowsing
    case leavePrivateBrowsing
    case closeTab
    case reopenTab
    case duplicateTab
    case togglePin
    case returnToPin
    case organizeTabs

    case reload
    case hardReload
    case stopLoading
    case goBack
    case goForward
    case find
    case copyLink
    case printPage
    case zoomIn
    case zoomOut
    case actualSize

    case splitRight
    case splitDown
    case otherPane
    case swapPanes
    case toggleSplitAxis
    case exitSplit
    case closeOtherPanes

    case toggleSidebar
    case toggleActivity
    case toggleFullScreen
    case toggleBrowser

    case toggleSpeech
    case toggleListening

    case showHistory
    case showDownloads
    case clearHistory
    case settings
    case extensions
    case checkForUpdates
}

enum CommandPaletteGroup: String, CaseIterable {
    case tabs
    case page
    case split
    case view
    case assistant
    case library

    var title: LocalizedStringResource {
        switch self {
        case .tabs:
            "Tabs"
        case .page:
            "Page"
        case .split:
            "Split View"
        case .view:
            "View"
        case .assistant:
            "Assistant"
        case .library:
            "Library"
        }
    }
}

struct CommandPaletteCommand {
    let id: String
    let group: CommandPaletteGroup
    let title: String
    var detail: String = ""
    var shortcut: String = ""
    let symbol: String
    var aliases: [String] = []
    var isAvailable = true
    var isSuggested = false
    let run: () -> Void
}

enum CommandMatch {
    static let strong = 450

    static func score(_ command: CommandPaletteCommand, for query: String) -> Int? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }

        let title = score(candidate: command.title, for: needle)
        let alias = command.aliases
            .map { score(candidate: $0, for: needle) * 3 / 5 }
            .max() ?? 0
        let best = max(title, alias)
        return best > 0 ? best : nil
    }

    private static func score(candidate: String, for needle: String) -> Int {
        let candidate = candidate.lowercased()
        let words = candidate.split { !$0.isLetter && !$0.isNumber }.map(String.init)

        if candidate == needle {
            return 1_000
        }
        if candidate.hasPrefix(needle) {
            return 700
        }
        if words.contains(where: { $0.hasPrefix(needle) }) {
            return 500
        }

        let terms = needle.split(separator: " ").map(String.init)
        if terms.count > 1, terms.allSatisfy({ term in words.contains { $0.hasPrefix(term) } }) {
            return 450
        }
        if candidate.contains(needle) {
            return 300
        }
        if needle.count >= 3, isSubsequence(needle, of: candidate) {
            return 120
        }
        return 0
    }

    private static func isSubsequence(_ needle: String, of candidate: String) -> Bool {
        var remaining = Substring(candidate)
        for character in needle where !character.isWhitespace {
            guard let index = remaining.firstIndex(of: character) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}

enum CommandPaletteCatalog {
    static func commands(
        context: CommandPaletteContext,
        perform: @escaping (CommandPaletteAction) -> Void
    ) -> [CommandPaletteCommand] {
        let builder = Builder(context: context, perform: perform)
        let all = builder.tabs + builder.page + builder.split + builder.view + builder.assistant + builder.library
        return all.filter(\.isAvailable)
    }

    static func suggested(_ commands: [CommandPaletteCommand]) -> [CommandPaletteCommand] {
        commands.filter(\.isSuggested)
    }

    static func items(_ commands: [CommandPaletteCommand]) -> [OmniboxItem] {
        commands.map { command in
            OmniboxItem(
                id: command.id,
                kind: .action,
                title: command.title,
                detail: command.detail,
                symbol: command.symbol,
                shortcut: command.shortcut,
                run: command.run
            )
        }
    }

    static func groupedSections(_ commands: [CommandPaletteCommand]) -> [OmniboxSection] {
        CommandPaletteGroup.allCases.compactMap { group in
            let members = commands.filter { $0.group == group }
            guard !members.isEmpty else { return nil }
            return OmniboxSection(
                id: "actions-\(group.rawValue)",
                title: String(localized: group.title),
                items: items(members)
            )
        }
    }

    static func matching(_ query: String, in commands: [CommandPaletteCommand]) -> [CommandPaletteCommand] {
        commands.enumerated()
            .compactMap { entry -> (index: Int, command: CommandPaletteCommand, score: Int)? in
                guard let score = CommandMatch.score(entry.element, for: query) else { return nil }
                return (entry.offset, entry.element, score)
            }
            .sorted { ($0.score, -$0.index) > ($1.score, -$1.index) }
            .map(\.command)
    }

    static func bestScore(_ query: String, in commands: [CommandPaletteCommand]) -> Int {
        commands.compactMap { CommandMatch.score($0, for: query) }.max() ?? 0
    }

    private struct Builder {
        let context: CommandPaletteContext
        let perform: (CommandPaletteAction) -> Void

        var tabs: [CommandPaletteCommand] {
            let pinTitle: LocalizedStringResource = context.isShowingPin ? "Remove Bookmark" : "Bookmark This Page"
            return [
                make(
                    .newTab,
                    group: .tabs,
                    title: "New Tab",
                    symbol: "plus",
                    shortcut: "⌘T",
                    aliases: ["open", "blank page", "window"],
                    isSuggested: true
                ),
                make(
                    .privateBrowsing,
                    group: .tabs,
                    title: "Private Browsing",
                    detail: "nothing is kept",
                    symbol: "eyeglasses",
                    shortcut: "⇧⌘N",
                    aliases: ["incognito", "private window", "anonymous"],
                    isAvailable: !context.isPrivate
                ),
                make(
                    .leavePrivateBrowsing,
                    group: .tabs,
                    title: "Leave Private Browsing",
                    symbol: "eyeglasses",
                    aliases: ["exit incognito", "normal browsing"],
                    isAvailable: context.isPrivate,
                    isSuggested: true
                ),
                make(
                    .reopenTab,
                    group: .tabs,
                    title: "Reopen Last Closed Tab",
                    symbol: "arrow.uturn.backward",
                    shortcut: "⇧⌘T",
                    aliases: ["restore", "undo close", "bring back"],
                    isAvailable: context.canReopenClosedTab,
                    isSuggested: true
                ),
                make(
                    .duplicateTab,
                    group: .tabs,
                    title: "Duplicate Tab",
                    symbol: "plus.square.on.square",
                    aliases: ["copy tab", "clone"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .closeTab,
                    group: .tabs,
                    title: "Close Tab",
                    symbol: "xmark",
                    shortcut: "⌘W",
                    aliases: ["close page"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .togglePin,
                    group: .tabs,
                    title: pinTitle,
                    symbol: context.isShowingPin ? "bookmark.slash" : "bookmark",
                    shortcut: "⌘D",
                    aliases: ["pin", "favourite", "favorite", "keep"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .returnToPin,
                    group: .tabs,
                    title: "Back to Bookmarked Page",
                    symbol: "bookmark",
                    shortcut: "⌥⌘D",
                    isAvailable: context.isAwayFromPin
                ),
                make(
                    .organizeTabs,
                    group: .tabs,
                    title: "Organize Tabs…",
                    detail: "group related tabs into folders",
                    symbol: "folder.badge.gearshape",
                    aliases: ["sort", "tidy", "group", "folders"],
                    isAvailable: context.tabCount > 1,
                    isSuggested: true
                ),
            ]
        }

        var page: [CommandPaletteCommand] {
            [
                make(
                    .reload,
                    group: .page,
                    title: "Reload Page",
                    symbol: "arrow.clockwise",
                    shortcut: "⌘R",
                    aliases: ["refresh"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .hardReload,
                    group: .page,
                    title: "Reload Page from Origin",
                    detail: "ignore the cache",
                    symbol: "arrow.2.circlepath",
                    shortcut: "⇧⌘R",
                    aliases: ["hard refresh", "empty cache"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .stopLoading,
                    group: .page,
                    title: "Stop Loading",
                    symbol: "xmark.circle",
                    shortcut: "⌘.",
                    isAvailable: context.isLoading
                ),
                make(
                    .goBack,
                    group: .page,
                    title: "Back",
                    symbol: "chevron.left",
                    shortcut: "⌘[",
                    aliases: ["previous page"],
                    isAvailable: context.canGoBack
                ),
                make(
                    .goForward,
                    group: .page,
                    title: "Forward",
                    symbol: "chevron.right",
                    shortcut: "⌘]",
                    aliases: ["next page"],
                    isAvailable: context.canGoForward
                ),
                make(
                    .find,
                    group: .page,
                    title: "Find on Page…",
                    symbol: "magnifyingglass",
                    shortcut: "⌘F",
                    aliases: ["search page", "look for text"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .copyLink,
                    group: .page,
                    title: "Copy Link",
                    symbol: "doc.on.doc",
                    shortcut: "⇧⌘C",
                    aliases: ["copy address", "copy url", "share"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .printPage,
                    group: .page,
                    title: "Print…",
                    symbol: "printer",
                    shortcut: "⌘P",
                    aliases: ["pdf", "paper"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .zoomIn,
                    group: .page,
                    title: "Zoom In",
                    symbol: "plus.magnifyingglass",
                    shortcut: "⌘+",
                    aliases: ["bigger text", "enlarge"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .zoomOut,
                    group: .page,
                    title: "Zoom Out",
                    symbol: "minus.magnifyingglass",
                    shortcut: "⌘-",
                    aliases: ["smaller text", "shrink"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .actualSize,
                    group: .page,
                    title: "Actual Size",
                    symbol: "1.magnifyingglass",
                    shortcut: "⌘0",
                    aliases: ["reset zoom", "100%"],
                    isAvailable: context.isZoomed
                ),
            ]
        }

        var split: [CommandPaletteCommand] {
            let axisTitle: LocalizedStringResource = context.isStacked ? "Place Side by Side" : "Stack Pages"
            return [
                make(
                    .splitRight,
                    group: .split,
                    title: "Split Right",
                    detail: "open a second page beside this one",
                    symbol: "rectangle.split.2x1",
                    shortcut: "⌃⌘→",
                    aliases: ["side by side", "two pages"],
                    isAvailable: context.canSplit
                ),
                make(
                    .splitDown,
                    group: .split,
                    title: "Split Down",
                    detail: "open a second page below this one",
                    symbol: "rectangle.split.1x2",
                    shortcut: "⌃⌘↓",
                    aliases: ["stacked", "two pages"],
                    isAvailable: context.canSplit
                ),
                make(
                    .otherPane,
                    group: .split,
                    title: "Other Pane",
                    symbol: "arrow.left.arrow.right",
                    shortcut: "⌥⌘]",
                    aliases: ["focus other page"],
                    isAvailable: context.isSplit
                ),
                make(
                    .swapPanes,
                    group: .split,
                    title: "Swap Panes",
                    symbol: "arrow.left.arrow.right",
                    aliases: ["exchange pages"],
                    isAvailable: context.canSwapPanes
                ),
                make(
                    .toggleSplitAxis,
                    group: .split,
                    title: axisTitle,
                    symbol: "rectangle.split.2x1",
                    isAvailable: context.hasSplitAxis
                ),
                make(
                    .exitSplit,
                    group: .split,
                    title: "Exit Split",
                    symbol: "rectangle",
                    aliases: ["one page", "unsplit"],
                    isAvailable: context.isSplit,
                    isSuggested: true
                ),
                make(
                    .closeOtherPanes,
                    group: .split,
                    title: "Close Other Pages",
                    symbol: "rectangle.badge.minus",
                    isAvailable: context.isSplit
                ),
            ]
        }

        var view: [CommandPaletteCommand] {
            let sidebarTitle: LocalizedStringResource = context.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            let activityTitle: LocalizedStringResource = context.isActivityVisible
                ? "Hide Agent Activity"
                : "Show Agent Activity"
            let fullScreenTitle: LocalizedStringResource = context.isFullScreen
                ? "Exit Full Screen"
                : "Enter Full Screen"
            let browserTitle: LocalizedStringResource = context.isBrowserVisible ? "Hide Browser" : "Show Browser"
            return [
                make(
                    .toggleSidebar,
                    group: .view,
                    title: sidebarTitle,
                    symbol: "sidebar.left",
                    shortcut: "⌃⌘S",
                    aliases: ["tabs list", "panel"]
                ),
                make(
                    .toggleActivity,
                    group: .view,
                    title: activityTitle,
                    detail: "what the assistant is doing",
                    symbol: "sparkle",
                    shortcut: "⌥⌘A",
                    aliases: ["inspector", "transcript", "log"]
                ),
                make(
                    .toggleFullScreen,
                    group: .view,
                    title: fullScreenTitle,
                    symbol: "arrow.up.left.and.arrow.down.right",
                    shortcut: "⌃⌘F"
                ),
                make(
                    .toggleBrowser,
                    group: .view,
                    title: browserTitle,
                    symbol: "globe",
                    shortcut: "⌥⌘B"
                ),
            ]
        }

        var assistant: [CommandPaletteCommand] {
            let voiceTitle: LocalizedStringResource = context.isSpeechMuted ? "Enable Voice" : "Disable Voice"
            let listenTitle: LocalizedStringResource = context.isListening ? "Stop Listening" : "Start Listening"
            return [
                make(
                    .toggleSpeech,
                    group: .assistant,
                    title: voiceTitle,
                    detail: "agent speech",
                    symbol: context.isSpeechMuted ? "speaker.wave.2" : "speaker.slash",
                    aliases: ["mute", "unmute", "sound", "speech", "read aloud"],
                    isSuggested: true
                ),
                make(
                    .toggleListening,
                    group: .assistant,
                    title: listenTitle,
                    symbol: context.isListening ? "mic.slash" : "mic",
                    aliases: ["microphone", "dictate", "talk", "voice input"]
                ),
            ]
        }

        var library: [CommandPaletteCommand] {
            [
                make(
                    .showHistory,
                    group: .library,
                    title: "Show All History",
                    symbol: "clock.arrow.circlepath",
                    shortcut: "⌘Y",
                    aliases: ["visited", "browsing history"]
                ),
                make(
                    .showDownloads,
                    group: .library,
                    title: "Downloads",
                    symbol: "square.and.arrow.down",
                    aliases: ["files", "saved", "received"]
                ),
                make(
                    .clearHistory,
                    group: .library,
                    title: "Clear History…",
                    detail: "\(context.historyCount) entries",
                    symbol: "trash",
                    aliases: ["delete browsing data", "erase", "forget"],
                    isAvailable: context.historyCount > 0,
                    isSuggested: true
                ),
                make(
                    .extensions,
                    group: .library,
                    title: "Extensions",
                    symbol: "puzzlepiece.extension",
                    aliases: ["add-ons", "plugins", "blockers"]
                ),
                make(
                    .settings,
                    group: .library,
                    title: "Settings",
                    detail: "model, voice, API key",
                    symbol: "gearshape",
                    shortcut: "⌘,",
                    aliases: ["preferences", "options", "config", "api key"],
                    isSuggested: true
                ),
                make(
                    .checkForUpdates,
                    group: .library,
                    title: "Check for Updates…",
                    symbol: "arrow.down.circle",
                    aliases: ["new version", "upgrade"],
                    isAvailable: context.canCheckForUpdates
                ),
            ]
        }

        private func make(
            _ action: CommandPaletteAction,
            group: CommandPaletteGroup,
            title: LocalizedStringResource,
            detail: LocalizedStringResource? = nil,
            symbol: String,
            shortcut: String = "",
            aliases: [String] = [],
            isAvailable: Bool = true,
            isSuggested: Bool = false
        ) -> CommandPaletteCommand {
            CommandPaletteCommand(
                id: "action-\(action.rawValue)",
                group: group,
                title: String(localized: title),
                detail: detail.map { String(localized: $0) } ?? "",
                shortcut: shortcut,
                symbol: symbol,
                aliases: aliases,
                isAvailable: isAvailable,
                isSuggested: isSuggested,
                run: { perform(action) }
            )
        }
    }
}
