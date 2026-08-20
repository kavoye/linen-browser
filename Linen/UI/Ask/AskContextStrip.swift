// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AskContextPage: Identifiable, Equatable {
    let id: UUID
    let title: String
    let host: String?
    let isAttached: Bool
}

enum AskContext {
    static func pages(browser: BrowserModel, mentionedTabIDs: [UUID]) -> [AskContextPage] {
        let onScreen = browser.splitPanes ?? [browser.activeTab].compactMap { $0 }
        var seen: Set<UUID> = []
        var pages = onScreen.compactMap { tab in
            seen.insert(tab.id).inserted ? page(tab, isAttached: false) : nil
        }
        pages += mentionedTabIDs.compactMap { id in
            guard let tab = browser.tabs.first(where: { $0.id == id }),
                  seen.insert(id).inserted
            else { return nil }
            return page(tab, isAttached: true)
        }
        return pages
    }

    private static func page(_ tab: BrowserTab, isAttached: Bool) -> AskContextPage {
        AskContextPage(
            id: tab.id,
            title: tab.title,
            host: URL(string: tab.urlString)?.displayHost,
            isAttached: isAttached
        )
    }
}

struct AskContextStrip: View {
    let pages: [AskContextPage]

    var body: some View {
        if !pages.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.Wash.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                ChipFlow(spacing: 6) {
                    Text("Can read")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 3)

                    ForEach(pages) { page in
                        AskPageChipView(
                            title: page.title,
                            host: page.host,
                            isAttached: page.isAttached,
                            fontSize: 10.5
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
