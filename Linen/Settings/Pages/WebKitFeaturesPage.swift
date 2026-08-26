// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct WebKitFeaturesPage: View {
    let onBack: () -> Void

    @State private var query = ""
    @State private var overrides = WebKitFeatures.overrides
    @FocusState private var searching: Bool

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
            caption: "These WebKit features are still in development and can break websites. Reload a page to apply your changes."
        )

        SearchFieldChrome {
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Font.secondary)
                .fieldPlaceholder("Search", isShowing: query.isEmpty)
                .focused($searching)
        }

        SettingsList {
            if matches.isEmpty {
                DetailRow(caption: "Nothing matches that.") {
                    EmptyView()
                }
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
        }
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
