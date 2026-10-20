// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

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

    private struct Builder {
        let context: CommandPaletteContext
        let perform: (CommandPaletteAction) -> Void

        var tabs: [CommandPaletteCommand] {
            let pinTitle: LocalizedStringResource = context.isShowingPin ? "Unpin Tab" : "Pin This Page"
            let indexedTabs = CommandPaletteAction.indexedTabs.enumerated().compactMap { index, action -> CommandPaletteCommand? in
                let slot = index + 1
                guard slot <= context.tabCount else { return nil }
                return make(
                    action,
                    group: .tabs,
                    title: "Show Tab \(slot)",
                    symbol: "square.on.square",
                    shortcut: "⌘\(slot)"
                )
            }
            return [
                make(
                    .newTab,
                    group: .tabs,
                    title: "New Tab",
                    symbol: "plus",
                    shortcut: "⌘T",
                    aliases: ["open tab", "new page"]
                ),
                make(
                    .openStartPage,
                    group: .tabs,
                    title: "Open Start Page",
                    symbol: "house",
                    shortcut: "",
                    aliases: ["start page", "new tab page", "home"],
                    isSuggested: true
                ),
                make(
                    .newWindow,
                    group: .tabs,
                    title: "New Window",
                    symbol: "macwindow.badge.plus",
                    shortcut: "⌘N"
                ),
                make(
                    .privateBrowsing,
                    group: .tabs,
                    title: "New Private Window",
                    symbol: "eyeglasses",
                    shortcut: "⇧⌘N",
                    aliases: ["incognito", "private window"]
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
                    .reopenWindow,
                    group: .tabs,
                    title: "Reopen Last Closed Window",
                    symbol: "macwindow",
                    aliases: ["restore window", "undo close window"],
                    isAvailable: context.canReopenClosedWindow
                ),
                make(
                    .showArchivedTabs,
                    group: .tabs,
                    title: "Show Archived Tabs",
                    detail: "\(context.archivedCount) tabs",
                    symbol: "archivebox",
                    aliases: ["archive", "archived", "auto archived", "old tabs"],
                    isAvailable: context.archivedCount > 0
                ),
                make(
                    .duplicateTab,
                    group: .tabs,
                    title: "Duplicate Tab",
                    symbol: "plus.square.on.square",
                    shortcut: "⇧⌘D",
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
                    symbol: context.isShowingPin ? "pin.slash" : "pin",
                    shortcut: "⌘D",
                    aliases: ["bookmark", "favourite", "favorite", "keep"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .returnToPin,
                    group: .tabs,
                    title: "Back to Pinned Page",
                    symbol: "pin",
                    shortcut: "⇧⌘H",
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
                make(
                    .nextTab,
                    group: .tabs,
                    title: "Show Next Tab",
                    symbol: "arrow.right.to.line",
                    shortcut: "⇧⌘]",
                    aliases: ["switch to next tab"],
                    isAvailable: context.tabCount > 1
                ),
                make(
                    .previousTab,
                    group: .tabs,
                    title: "Show Previous Tab",
                    symbol: "arrow.left.to.line",
                    shortcut: "⇧⌘[",
                    aliases: ["switch to previous tab"],
                    isAvailable: context.tabCount > 1
                ),
                make(
                    .lastTab,
                    group: .tabs,
                    title: "Show Last Tab",
                    symbol: "arrow.right.to.line",
                    shortcut: "⌘9",
                    isAvailable: context.tabCount > 1
                ),
            ] + indexedTabs
        }

        var page: [CommandPaletteCommand] {
            [
                make(
                    .openLocation,
                    group: .page,
                    title: "Open Location…",
                    symbol: "link",
                    shortcut: "⌘L",
                    aliases: ["address bar", "enter url", "website address"]
                ),
                make(
                    .reload,
                    group: .page,
                    title: "Reload Page",
                    symbol: "arrow.clockwise",
                    shortcut: "⌘R",
                    aliases: ["refresh"],
                    isAvailable: context.canReload
                ),
                make(
                    .hardReload,
                    group: .page,
                    title: "Reload Page from Origin",
                    detail: "ignore the cache",
                    symbol: "arrow.2.circlepath",
                    shortcut: "⇧⌘R",
                    aliases: ["hard refresh", "empty cache"],
                    isAvailable: context.canReload
                ),
                make(
                    .stopLoading,
                    group: .page,
                    title: "Stop",
                    symbol: "xmark.circle",
                    shortcut: "⌘.",
                    aliases: ["stop loading"],
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
                    title: "Find…",
                    symbol: "magnifyingglass",
                    shortcut: "⌘F",
                    aliases: ["find on page", "search page", "look for text"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .findNext,
                    group: .page,
                    title: "Find Next",
                    symbol: "chevron.down",
                    shortcut: "⌘G",
                    aliases: ["next match", "next search result"],
                    isAvailable: context.hasActiveTab
                ),
                make(
                    .findPrevious,
                    group: .page,
                    title: "Find Previous",
                    symbol: "chevron.up",
                    shortcut: "⇧⌘G",
                    aliases: ["previous match", "previous search result"],
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
                make(
                    .translatePage,
                    group: .page,
                    title: translationTitle,
                    symbol: "translate",
                    aliases: ["translate", "language", "view original"],
                    isAvailable: context.canTranslate
                ),
                make(
                    .showWebInspector,
                    group: .page,
                    title: "Show Web Inspector",
                    symbol: "hammer",
                    shortcut: "⌥⌘I",
                    aliases: ["inspect element", "developer tools", "devtools", "console"],
                    isAvailable: context.canInspect
                ),
                make(
                    .copyScreenshot,
                    group: .page,
                    title: "Copy Screenshot",
                    symbol: "camera.viewfinder",
                    aliases: ["screenshot", "take screenshot", "capture page", "snapshot"],
                    isAvailable: context.canScreenshot
                ),
            ]
        }

        private var translationTitle: LocalizedStringResource {
            context.isTranslated ? "View Original" : "Translate Page"
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
            let sidePanelTitle: LocalizedStringResource = context.isSidePanelVisible
                ? "Hide Side Panel"
                : "Show Side Panel"
            let fullScreenTitle: LocalizedStringResource = context.isFullScreen
                ? "Exit Full Screen"
                : "Enter Full Screen"
            let windowStyleTitle: LocalizedStringResource = context.isMinimal
                ? "Use Standard Window Style"
                : "Use Minimal Window Style"
            let barTitle: LocalizedStringResource = context.isBarOnTop ? "Move Bar to Bottom" : "Move Bar to Top"
            return [
                make(
                    .toggleSidebar,
                    group: .view,
                    title: sidebarTitle,
                    symbol: "sidebar.left",
                    shortcut: "⌃⌘S",
                    aliases: ["tabs list", "panel"],
                    isAvailable: !context.isMinimal
                ),
                make(
                    .toggleMinimal,
                    group: .view,
                    title: windowStyleTitle,
                    symbol: context.isMinimal ? "macwindow" : "rectangle.dashed",
                    shortcut: "⇧⌘M",
                    aliases: ["minimal", "standard", "window style", "focus", "zen", "simple",
                              "hide toolbar", "distraction", "layout",
                    ]
                ),
                make(
                    .moveMinimalBar,
                    group: .view,
                    title: barTitle,
                    symbol: context.isBarOnTop ? "arrow.down.to.line" : "arrow.up.to.line",
                    aliases: ["bar position", "address bar", "floating bar", "top", "bottom"],
                    isAvailable: context.isMinimal
                ),
                make(
                    .toggleSidePanel,
                    group: .view,
                    title: sidePanelTitle,
                    symbol: "sidebar.right",
                    shortcut: "⌥⌘S",
                    aliases: ["assistant", "inspector", "lyrics"]
                ),
                make(
                    .toggleFullScreen,
                    group: .view,
                    title: fullScreenTitle,
                    symbol: "arrow.up.left.and.arrow.down.right",
                    shortcut: "⌃⌘F"
                ),
                make(
                    .minimizeWindow,
                    group: .view,
                    title: "Minimize",
                    symbol: "minus.square",
                    shortcut: "⌘M",
                    aliases: ["minimize window"]
                ),
                make(
                    .closeWindow,
                    group: .view,
                    title: "Close Window",
                    symbol: "xmark.square",
                    shortcut: "⇧⌘W"
                ),
            ]
        }

        var assistant: [CommandPaletteCommand] {
            let voiceTitle: LocalizedStringResource
            if context.isSpeechMuted {
                voiceTitle = "Speak Answers Automatically"
            } else {
                voiceTitle = "Stop Speaking Answers Automatically"
            }
            let listenTitle: LocalizedStringResource = context.isListening ? "Stop Listening" : "Start Listening"
            return [
                make(
                    .toggleSpeech,
                    group: .assistant,
                    title: voiceTitle,
                    detail: "agent speech",
                    symbol: context.isSpeechMuted ? "speaker.wave.2" : "speaker.slash",
                    aliases: ["mute", "unmute", "sound", "speech", "read aloud", "voice"],
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
                    title: "Settings…",
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
                make(
                    .releaseNotes,
                    group: .library,
                    title: "Release Notes…",
                    symbol: "doc.text",
                    aliases: ["what's new", "whats new", "changelog", "notes", "version"]
                ),
                make(
                    .aboutLinen,
                    group: .library,
                    title: "About Linen",
                    symbol: "info.circle",
                    aliases: ["app version", "credits"]
                ),
                make(
                    .quitLinen,
                    group: .library,
                    title: "Quit Linen",
                    symbol: "power",
                    shortcut: "⌘Q",
                    aliases: ["exit app", "quit browser"]
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
