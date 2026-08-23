// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct StartPage: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    nonisolated static let verticalInset: CGFloat = 56

    @State private var availableHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                StartPageOverview(
                    browser: browser,
                    coordinator: coordinator,
                    availableHeight: availableHeight
                )
                .frame(maxWidth: 780)
                .padding(.horizontal, 32)
                .padding(.vertical, Self.verticalInset)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
                    - Self.verticalInset * 2
            } action: { height in
                availableHeight = max(0, height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectHidden(true, for: [.top, .bottom])

            EditStartPageButton(settings: coordinator.settings)
                .padding(20)
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
    }
}

private struct StartPageOverview: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let availableHeight: CGFloat

    var body: some View {
        let snapshot = StartPageSnapshot(
            historyEntries: browser.history.entries,
            historyVisits: browser.history.visits,
            downloads: browser.downloads.items,
            tasks: coordinator.conversationLog.traces,
            hiddenFrequentHosts: coordinator.settings.hiddenFrequentHosts
        )
        let sections = snapshot.visibleSections(
            in: coordinator.settings.startPageOrder,
            isShown: coordinator.settings.showsStartPageSection
        )

        VStack(spacing: 34) {
            StartPageHero(browser: browser, coordinator: coordinator)
                .zIndex(1)

            if !sections.isEmpty {
                StartPageSections(
                    sections: sections,
                    browser: browser,
                    coordinator: coordinator
                )
            }
        }
        .padding(.bottom, sections.isEmpty ? 0 : 32)
        .frame(minHeight: sections.isEmpty ? availableHeight : nil)
    }
}

private struct StartPageHero: View {
    private struct Suggestion: Identifiable {
        let symbol: String
        let label: LocalizedStringResource
        let ask: String

        var id: String {
            ask
        }
    }

    let browser: BrowserModel
    let coordinator: AppCoordinator

    private static let suggestions = [
        Suggestion(symbol: "newspaper", label: "What’s on Hacker News?", ask: "what’s on hacker news right now?"),
        Suggestion(symbol: "music.note", label: "Play chill lofi", ask: "play chill lofi"),
        Suggestion(symbol: "bag", label: "Find Nike Pegasus 42", ask: "find nike pegasus 42"),
    ]

    private var heading: LocalizedStringResource {
        Omnibox.isAgentOnly ? "Ask anything" : "Search anything"
    }

    var body: some View {
        VStack(spacing: 0) {
            LiveWaveform(isListening: coordinator.state == .listening)
                .padding(.bottom, 16)

            Text(heading)
                .font(.system(size: 26, weight: .semibold))
                .padding(.bottom, 18)

            AskSurface(placement: .startPage, browser: browser, coordinator: coordinator)
            .frame(maxWidth: 520)
            .padding(.bottom, 14)
            .zIndex(1)

            HStack(spacing: 8) {
                ForEach(Self.suggestions) { suggestion in
                    SuggestionChip(symbol: suggestion.symbol, label: suggestion.label) {
                        Task { await coordinator.handleTypedUtterance(suggestion.ask) }
                    }
                }
            }
        }
    }
}
