// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AdvancedSettings: View {
    @Bindable var settings: BrowserSettings
    var mcpServer: BrowserMCPServer?
    var highlight: String?

    @FocusState private var customFieldFocused: Bool
    @State private var confirmingReset = false
    @Environment(\.settingsRouter) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            if router.path == ["mcp"], let mcpServer {
                MCPSettingsPage(server: mcpServer) { router.back() }
            } else if router.path == ["webkit-features"] {
                WebKitFeaturesPage { router.back() }
            } else {
                page
            }
        }
        .onChange(of: highlight, initial: true) { _, anchor in
            guard let anchor, anchor.hasPrefix("advanced.") else { return }
            switch anchor {
            case "advanced.mcp":
                router.open(["mcp"])
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
                title: "Certificate exceptions",
                caption: "Continue past a certificate macOS rejects. Linen removes the exception when you quit."
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

        if mcpServer != nil {
            SettingsCard {
                DrillInRow(
                    title: "External connections", symbol: "cable.connector",
                    caption: "Connect an external assistant to tabs you choose."
                ) {
                    router.open(["mcp"])
                }
                .settingsAnchor("advanced.mcp")
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
