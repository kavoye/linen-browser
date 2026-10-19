// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AdvancedSettings: View {
    @Bindable var settings: BrowserSettings
    var highlight: String?

    @FocusState private var customFieldFocused: Bool
    @State private var confirmingReset = false
    @Environment(\.settingsRouter) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if router.path == ["webkit-features"] {
                WebKitFeaturesPage { router.back() }
            } else {
                page
            }
        }
        .onChange(of: highlight, initial: true) { _, anchor in
            guard let anchor, anchor.hasPrefix("advanced.") else { return }
            switch anchor {
            case "advanced.features":
                router.open(["webkit-features"])
            default:
                router.back()
            }
        }
    }

    @ViewBuilder private var page: some View {
        SettingsPageHeader(title: "Advanced")

        SettingsCard {
            DetailRow(
                title: "Web Inspector",
                caption: "Add Inspect Element to a page’s right-click menu."
            ) {
                SettingsToggle($settings.webInspectorEnabled)
            }
            .settingsAnchor("advanced.inspector")

            RowSeparator()

            DetailRow(
                title: "Allow untrusted certificates",
                caption: "Open a website even if its certificate isn’t trusted. Linen forgets your choice when you quit."
            ) {
                SettingsToggle($settings.allowsCertificateExceptions)
            }
            .settingsAnchor("advanced.certificates")

            if WebKitFeatures.isAvailable {
                RowSeparator()

                DrillInRow(
                    title: "Feature flags",
                    caption: "Experimental WebKit features may break websites."
                ) {
                    router.open(["webkit-features"])
                }
                .settingsAnchor("advanced.features")
            }

            RowSeparator()

            DetailRow(
                title: "User agent",
                caption: "Some websites may not work with a custom user agent."
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

        SettingsCard {
            DetailRow(
                title: "Reset settings",
                caption: "Put appearance, search, privacy, websites, and downloads back to their defaults."
            ) {
                SettingsButton(title: "Reset…", isDestructive: true) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $confirmingReset
                ) {
                    Button("Reset settings", role: .destructive) { settings.resetToDefaults() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("""
                        Appearance, search, privacy, websites, and downloads go back to their \
                        defaults. Tabs, history, shortcuts, and your provider are not affected.
                        """)
                }
            }
            .settingsAnchor("advanced.reset")
        }
    }
}
