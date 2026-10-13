// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct WebKitFeaturesPage: View {
    let onBack: () -> Void

    @State private var query = ""
    @State private var overrides = WebKitFeatures.overrides

    private var matches: [WebKitFeature] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return WebKitFeatures.all }
        return WebKitFeatures.all.filter {
            $0.name.lowercased().contains(needle)
                || $0.key.lowercased().contains(needle)
                || $0.details.lowercased().contains(needle)
        }
    }

    var body: some View {
        SubPageHeader(backTitle: "Advanced", onBack: onBack) {
            if !overrides.isEmpty {
                SettingsButton(title: "Reset", isDestructive: true) {
                    WebKitFeatures.resetAll()
                    overrides = [:]
                }
            }
        }

        SettingsPageHeader(
            title: "Feature flags",
            caption: "Experimental features may break websites. Reload the page to apply changes."
        )

        SettingsSection(title: "Features", symbol: "flag", isLongList: true, accessory: {
            ToolbarSearchField(query: $query, placeholder: "Search features")
        }, content: {
            if matches.isEmpty {
                SettingsEmptyState(symbol: "magnifyingglass", title: "No matches", caption: "No features match your search.")
            }

            ForEach(Array(matches.enumerated()), id: \.element.id) { index, feature in
                if index > 0 {
                    RowSeparator()
                }

                DetailRow(
                    verbatimTitle: feature.name,
                    verbatimCaption: feature.details.isEmpty ? nil : feature.details
                ) {
                    SettingsToggle(binding(to: feature))
                }
            }
        })
    }

    private func binding(to feature: WebKitFeature) -> Binding<Bool> {
        Binding(
            get: { overrides[feature.key] ?? feature.isOnByDefault },
            set: { isOn in
                WebKitFeatures.setOn(isOn, feature)
                overrides = WebKitFeatures.overrides
            }
        )
    }
}
