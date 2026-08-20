// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AdvancedSettings: View {
    @Bindable var settings: BrowserSettings

    @FocusState private var customFieldFocused: Bool
    @State private var confirmingReset = false

    var body: some View {
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
                caption: "Continue past a certificate macOS rejects. Forgotten when you quit."
            ) {
                SettingsToggle($settings.allowsCertificateExceptions)
            }
            .settingsAnchor("advanced.certificates")

            RowSeparator()

            DetailRow(
                title: "User agent",
                caption: "Linen uses the system user agent. Changing this can break websites."
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
                        TextField(WebViewPool.safariUserAgent, text: $settings.customUserAgent)
                            .textFieldStyle(.plain)
                            .font(Theme.Font.label)
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
