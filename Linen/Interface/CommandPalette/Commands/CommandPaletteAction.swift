// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct CommandPaletteContext {
    var isSpeechMuted = false
    var isListening = false
    var historyCount = 0
    var tabCount = 0
    var hasActiveTab = false
    var canReload = false
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var isZoomed = false
    var isTranslated = false
    var canTranslate = false
    var canInspect = false
    var isShowingPin = false
    var isAwayFromPin = false
    var canReopenClosedTab = false
    var canReopenClosedWindow = false
    var archivedCount = 0
    var canSplit = false
    var isSplit = false
    var canSwapPanes = false
    var isStacked = false
    var hasSplitAxis = false
    var isSidebarVisible = true
    var isSidePanelVisible = false
    var isMinimal = false
    var isBarOnTop = false
    var isFullScreen = false
    var canCheckForUpdates = false
}

enum CommandPaletteAction: String, CaseIterable {
    static let indexedTabs: [Self] = [
        .showTab1, .showTab2, .showTab3, .showTab4,
        .showTab5, .showTab6, .showTab7, .showTab8,
    ]

    case newTab
    case newWindow
    case openStartPage
    case openLocation
    case privateBrowsing
    case closeTab
    case reopenTab
    case reopenWindow
    case showArchivedTabs
    case duplicateTab
    case togglePin
    case returnToPin
    case organizeTabs
    case nextTab
    case previousTab
    case lastTab
    case showTab1
    case showTab2
    case showTab3
    case showTab4
    case showTab5
    case showTab6
    case showTab7
    case showTab8

    case reload
    case hardReload
    case stopLoading
    case goBack
    case goForward
    case find
    case findNext
    case findPrevious
    case copyLink
    case printPage
    case zoomIn
    case zoomOut
    case actualSize
    case translatePage
    case showWebInspector

    case splitRight
    case splitDown
    case otherPane
    case swapPanes
    case toggleSplitAxis
    case exitSplit
    case closeOtherPanes

    case toggleSidebar
    case toggleSidePanel
    case toggleMinimal
    case moveMinimalBar
    case toggleFullScreen
    case closeWindow
    case minimizeWindow

    case toggleSpeech
    case toggleListening

    case showHistory
    case showDownloads
    case clearHistory
    case settings
    case extensions
    case checkForUpdates
    case releaseNotes
    case aboutLinen
    case quitLinen
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
