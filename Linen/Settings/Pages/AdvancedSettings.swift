// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AdvancedSettings: View {
    @Bindable var settings: BrowserSettings

    @FocusState private var customFieldFocused: Bool
    @State private var confirmingReset = false
    @State private var readingFeatures = false

    var body: some View {
        if readingFeatures {
            WebKitFeaturesPage { readingFeatures = false }
        } else {
            page
        }
    }

    @ViewBuilder private var page: some View {
        SettingsPageHeader(title: "Advanced")

        SettingsCard {
            DetailRow(
                title: "Web Inspector",
                caption: "Adds Inspect Element to the page’s right-click menu."
            ) {
                SettingsToggle($settings.webInspectorEnabled)
            }
            .settingsAnchor("advanced.inspector")

            RowSeparator()

            DetailRow(
                title: "Certificate exceptions",
                caption: "Continue past a certificate macOS rejects. Forgotten on quit."
            ) {
                SettingsToggle($settings.allowsCertificateExceptions)
            }
            .settingsAnchor("advanced.certificates")

            if WebKitFeatures.isAvailable {
                RowSeparator()

                DrillInRow(
                    title: "Feature flags",
                    caption: "WebKit’s own experiments, which can break websites."
                ) {
                    readingFeatures = true
                }
                .settingsAnchor("advanced.features")
            }

            RowSeparator()

            DetailRow(
                title: "User agent",
                caption: "Changing this can break websites."
            ) {
                SegmentedControl(
                    items: UserAgentMode.allCases.map { .init(value: $0, label: $0.label) },
                    selection: settings.userAgentMode,
                    onSelect: { settings.userAgentMode = $0 }
                )
            }
            .settingsAnchor("advanced.userAgent")

            if settings.userAgentMode == .custom {
                RowSeparator()

                DetailRow(caption: "Leave empty to use the system default.", layout: .stacked) {
                    FieldChrome(isFocused: customFieldFocused) {
                        TextField("", text: $settings.customUserAgent)
                            .textFieldStyle(.plain)
                            .font(Theme.Font.label)
                            .fieldPlaceholder(
                                verbatim: WebViewPool.safariUserAgent,
                                isShowing: settings.customUserAgent.isEmpty
                            )
                            .focused($customFieldFocused)
                    }
                }
            }
        }

        SettingsSection(title: "Reset", symbol: "arrow.counterclockwise") {
            DetailRow(title: "Reset settings") {
                SettingsButton(title: "Reset…", isDestructive: true) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $confirmingReset
                ) {
                    Button("Reset Settings", role: .destructive) { settings.resetToDefaults() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("""
                        Appearance, search, privacy, websites, and downloads go back to their \
                        defaults. Tabs, history, shortcuts, and your provider aren’t affected.
                        """)
                }
            }
            .settingsAnchor("advanced.reset")
        }
    }
}
