// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

struct WebsiteDataPage: View {
    let onBack: () -> Void

    @State private var entries: [WebsiteData.Entry] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var removingName: String?
    @State private var confirmingRemoveAll = false

    @FocusState private var searchFocused: Bool

    private var shown: [WebsiteData.Entry] {
        entries.filter { WebsiteData.matches($0, query: query) }
    }

    var body: some View {
        SubPageHeader(backTitle: "Privacy", onBack: onBack)

        SettingsPageHeader(
            title: "Website data",
            caption: "Websites use this data to keep you signed in and remember your preferences."
        )

        SettingsSection(title: "Stored on this Mac", symbol: "internaldrive", accessory: {
            if !entries.isEmpty {
                searchField
            }
        }, content: {
            if isLoading {
                loading
            } else if entries.isEmpty {
                SettingsEmptyState(
                    symbol: "internaldrive",
                    title: "No website data",
                    caption: "No website stores data on this Mac."
                )
            } else if shown.isEmpty {
                SettingsEmptyState(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    caption: "No website matches what you typed."
                )
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        RowSeparator()
                    }
                    SiteRow(host: entry.displayName, summary: entry.summary) {
                        SettingsButton(title: "Remove…", isDestructive: true) {
                            removingName = entry.displayName
                        }
                    }
                }
            }
        })
        .settingsAnchor("privacy.storage")
        .confirmationDialog(
            removingName.map {
                Text("Remove the data stored by “\($0)”?")
            } ?? Text(verbatim: ""),
            isPresented: Binding(get: { removingName != nil }, set: { if !$0 { removingName = nil } })
        ) {
            Button("Remove", role: .destructive) {
                guard let name = removingName else { return }
                Task { await remove([name]) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’re signed out of this website, and its preferences are removed.")
        }

        if !entries.isEmpty {
            SectionActions {
                SettingsButton(title: "Remove All…", isDestructive: true) {
                    confirmingRemoveAll = true
                }
            }
            .confirmationDialog(
                "Remove the data stored by every website?",
                isPresented: $confirmingRemoveAll
            ) {
                Button("Remove All", role: .destructive) {
                    Task { await remove(Set(entries.map(\.displayName))) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’re signed out of \(entries.count) websites, and their preferences are removed. Your history and downloads stay.")
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            Spinner(size: 12)
                .foregroundStyle(.secondary)
            Text("Counting…")
                .font(Theme.Font.secondary)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, SettingsMetrics.rowPaddingV)
        .task { await reload() }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search websites", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Font.label)
                .focused($searchFocused)
                .frame(width: 130)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(SettingsMetrics.fill, in: RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius)
                .strokeBorder(searchFocused ? Theme.Wash.outline : SettingsMetrics.border, lineWidth: 1)
        )
    }

    private func reload() async {
        entries = await WebsiteData.entries(in: BrowsingData.store)
        isLoading = false
    }

    private func remove(_ names: Set<String>) async {
        await WebsiteData.remove(names, from: BrowsingData.store)
        await reload()
    }
}
