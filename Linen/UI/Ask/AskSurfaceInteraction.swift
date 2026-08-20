// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

enum AskSurfaceSubmission: Equatable {
    case none
    case result(Int)
    case ask(String)
    case navigate(String)
}

struct AskSurfaceInteraction: Equatable {
    var text = "" {
        didSet {
            if oldValue != text {
                selection = 0
            }
        }
    }
    var selection = 0
    var rowHeight: CGFloat = 0

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func moveSelection(by delta: Int, resultCount: Int) {
        selection = OmniboxSelection.moved(from: selection, by: delta, resultCount: resultCount)
    }

    mutating func moveSection(by delta: Int, itemCounts: [Int]) {
        selection = OmniboxSelection.movedBySection(from: selection, by: delta, itemCounts: itemCounts)
    }

    func submission(resultCount: Int, agentOnly: Bool, hasMentions: Bool = false) -> AskSurfaceSubmission {
        let input = trimmedText
        guard !input.isEmpty else { return .none }
        if (0..<resultCount).contains(selection) {
            return .result(selection)
        }
        if let prompt = Self.agentPrompt(in: input) {
            return prompt.isEmpty ? .none : .ask(prompt)
        }
        if hasMentions {
            return .ask(input)
        }
        if agentOnly, Omnibox.location(for: input) == nil {
            return .ask(input)
        }
        return .navigate(input)
    }

    func commandSubmission() -> AskSurfaceSubmission {
        let input = trimmedText
        guard !input.isEmpty else { return .none }
        let prompt = Self.agentPrompt(in: input) ?? input
        return prompt.isEmpty ? .none : .ask(prompt)
    }

    mutating func finish(restingText: String) {
        text = restingText
        selection = 0
    }

    mutating func cancel(mirrorsPageURL: Bool, currentURL: String) {
        if mirrorsPageURL {
            text = currentURL
        }
        selection = 0
    }

    static func agentPrompt(in input: String) -> String? {
        guard input.hasPrefix("@") else { return nil }
        return String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    static func mentionFragment(in text: String) -> String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@"),
              text.count > last.count
        else { return nil }
        return String(last.dropFirst()).lowercased()
    }

    static func removingMentionFragment(from text: String) -> String {
        guard mentionFragment(in: text) != nil,
              let at = text.lastIndex(of: "@")
        else { return text }
        return String(text[..<at])
    }
}

enum AskRestingContent: Equatable {
    case transcript(String)
    case agent(String)
    case notice(String)
    case status(String)
    case placeholder(String)
    case address(String)

    var isCentred: Bool {
        switch self {
        case .address, .notice:
            true
        case .transcript, .agent, .status, .placeholder:
            false
        }
    }

    func accessibilityValue(fallback: String) -> String {
        switch self {
        case .transcript(let text):
            text.isEmpty ? String(localized: "Listening…") : text
        case .agent(let text):
            String(localized: "AI reply: \(text)")
        case .notice(let text), .status(let text):
            text
        case .placeholder:
            ""
        case .address:
            fallback
        }
    }

    // swiftlint:disable:next function_parameter_count
    static func resolve(
        isListening: Bool,
        transcript: String,
        agentMessage: String?,
        mirrorsPageURL: Bool,
        isFocused: Bool,
        typedText: String,
        notice: String?,
        status: String?,
        placeholder: String,
        currentURL: String
    ) -> AskRestingContent? {
        if isListening {
            return .transcript(transcript)
        }
        let yieldsToTyping = mirrorsPageURL ? !isFocused : typedText.isEmpty
        if let agentMessage, yieldsToTyping {
            return .agent(agentMessage)
        }
        if let notice, yieldsToTyping {
            return .notice(notice)
        }
        if let status, yieldsToTyping {
            return .status(status)
        }
        guard mirrorsPageURL, !isFocused else { return nil }
        let address = displayAddress(for: currentURL)
        return address.isEmpty ? .placeholder(placeholder) : .address(address)
    }

    static func displayAddress(for value: String) -> String {
        guard let url = URL(string: value), let host = url.host() else { return value }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct AskSurfaceActivity: Equatable {
    let count: Int
    let isRunning: Bool
    let isThinking: Bool

    static let none = AskSurfaceActivity(count: 0, isRunning: false, isThinking: false)
}

enum AskSurfaceResults {
    static let historyLimit = 2
    static let tabLimit = 1

    // swiftlint:disable:next function_parameter_count
    static func sections(
        placement: AskSurface.Placement,
        query: String,
        isFocused: Bool,
        isListening: Bool,
        currentURL: String,
        agentOnly: Bool,
        agentName: String,
        history: HistoryStore,
        tabs: [BrowserTab],
        mentions: [MentionChip] = [],
        activeTabID: UUID? = nil,
        phrases: [String],
        open: @escaping (URL) -> Void,
        switchTo: @escaping (BrowserTab) -> Void,
        mention: @escaping (BrowserTab) -> Void = { _ in },
        ask: @escaping (String) -> Void
    ) -> [OmniboxSection] {
        guard isFocused, !isListening else { return [] }
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        if placement.mirrorsPageURL, input == currentURL {
            return []
        }

        if let fragment = AskSurfaceInteraction.mentionFragment(in: query) {
            let section = mentionSection(
                fragment: fragment,
                tabs: tabs,
                mentions: mentions,
                activeTabID: activeTabID,
                mention: mention
            )
            return [section].compactMap { $0 }
        }

        if let prompt = AskSurfaceInteraction.agentPrompt(in: input) {
            return prompt.isEmpty ? [] : [askSection(prompt, agentName: agentName, ask: ask)]
        }

        if !mentions.isEmpty {
            let prompt = MentionText.resolved(input, chips: mentions)
            return [askSection(prompt, agentName: agentName, ask: ask)]
        }

        if agentOnly {
            return [
                Omnibox.topSection(query: input, open: open),
                askSection(input, agentName: agentName, ask: ask),
                Omnibox.historySection(query: input, store: history, limit: historyLimit, open: open),
                Omnibox.tabsSection(query: input, tabs: tabs, limit: tabLimit, switchTo: switchTo),
            ].compactMap { $0 }
        }

        var result = [
            Omnibox.topSection(query: input, open: open),
            Omnibox.historySection(query: input, store: history, limit: historyLimit, open: open),
            Omnibox.tabsSection(query: input, tabs: tabs, limit: tabLimit, switchTo: switchTo),
            Omnibox.phrasesSection(query: input, phrases: phrases, limit: 6, open: open),
        ].compactMap { $0 }
        result.append(askSection(input, agentName: agentName, ask: ask))
        return result
    }

    private static func mentionSection(
        fragment: String,
        tabs: [BrowserTab],
        mentions: [MentionChip],
        activeTabID: UUID?,
        mention: @escaping (BrowserTab) -> Void
    ) -> OmniboxSection? {
        let candidates = tabs.filter { tab in
            tab.id != activeTabID
                && !mentions.contains { $0.id == tab.id }
                && (fragment.isEmpty
                    || tab.title.lowercased().contains(fragment)
                    || tab.urlString.lowercased().contains(fragment))
        }
        let items = candidates.prefix(5).map { tab in
            let host = URL(string: tab.urlString)?.displayHost
            return OmniboxItem(
                id: "mention-\(tab.id)",
                kind: .tab,
                title: tab.title,
                detail: [host, String(localized: "The assistant can read it for this question")]
                    .compactMap { $0 }
                    .joined(separator: " • "),
                iconHost: host
            ) {
                mention(tab)
            }
        }
        guard !items.isEmpty else { return nil }
        return OmniboxSection(id: "mention", title: String(localized: "Attach Tab"), items: Array(items))
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
                OmniboxItem(id: "ask-agent", kind: .ask, title: prompt) {
                    ask(prompt)
                },
            ]
        )
    }
}
