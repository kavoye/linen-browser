// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SearchSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    @FocusState private var focus: Field?

    private enum Field { case name, address }

    private static let searchTermToken = "%s"

    private var engine: SearchEngine {
        settings.searchEngine
    }
    private var engineWorks: Bool {
        engine.searchURL(for: "test") != nil
    }

    private var suggestionsCaption: LocalizedStringResource {
        engine.suggestTemplate == nil
            ? "\(engine.name) doesn’t offer suggestions."
            : "Suggestions from \(engine.name) appear as you type."
    }

    private var engineOptions: [SettingsMenu<String>.Option] {
        SearchEngine.catalog.map { .init(value: $0.id, label: $0.name) }
            + [.init(value: SearchEngine.customID, label: String(localized: "Something else…"))]
    }

    var body: some View {
        SettingsPageHeader(title: "Search")

        SettingsCard {
            DetailRow(title: "Search engine") {
                SettingsMenu(options: engineOptions, selection: $settings.searchEngineID)
            }
            .settingsAnchor("search.engine")

            if engine.isCustom {
                RowSeparator()

                DetailRow(
                    title: "Search URL",
                    caption: "Use \(Self.searchTermToken) where the search term goes.",
                    layout: .stacked
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldChrome(isFocused: focus == .address) {
                            TextField(text: $settings.customSearchTemplate) {
                                Text(verbatim: "https://example.com/search?q=")
                            }
                                .textFieldStyle(.plain)
                                .font(Theme.Font.body)
                                .focused($focus, equals: .address)
                        }

                        FieldChrome(isFocused: focus == .name) {
                            TextField("Name", text: $settings.customSearchName)
                                .textFieldStyle(.plain)
                                .font(Theme.Font.body)
                                .focused($focus, equals: .name)
                        }

                        if !settings.customSearchTemplate.isEmpty, !engineWorks {
                            SettingsNotice(
                                symbol: "exclamationmark.triangle.fill",
                                text: String(localized: "Linen can’t search with this URL. DuckDuckGo is answering instead.")
                            )
                        }
                    }
                }
                .settingsAnchor("search.custom")
            }

            if !settings.agentOnlyInput {
                RowSeparator()

                DetailRow(
                    title: "Search suggestions",
                    caption: suggestionsCaption
                ) {
                    SettingsToggle($settings.showsSearchSuggestions)
                        .disabled(engine.suggestTemplate == nil)
                        .opacity(engine.suggestTemplate == nil ? 0.45 : 1)
                }
                .settingsAnchor("search.suggestions")
            }
        }

        SettingsSection(title: "Address bar", symbol: "character.cursor.ibeam") {
            DetailRow(
                title: "Always ask the assistant",
                caption: "Questions go to \(coordinator.agentDisplayName). Links still open normally."
            ) {
                SettingsToggle($settings.agentOnlyInput)
            }
            .settingsAnchor("general.agentOnly")
        }
    }
}
