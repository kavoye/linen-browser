// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AppearanceSettings: View {
    let coordinator: AppCoordinator

    @Bindable var settings: BrowserSettings

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    private static let sizes: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2]

    var body: some View {
        SettingsPageHeader(title: "Appearance")

        SettingsCard {
            DetailRow(title: "Theme", layout: .stacked) {
                ThemePicker(selection: settings.appearance) { settings.appearance = $0 }
            }
            .settingsAnchor("appearance.theme")

            RowSeparator()

            DetailRow(
                title: "Page zoom",
                caption: "The default for every website. Tabs can still be zoomed."
            ) {
                SettingsMenu(
                    options: Self.sizes.map {
                        .init(
                            value: $0,
                            label: $0.formatted(
                                .percent.precision(.fractionLength(0))
                            )
                        )
                    },
                    selection: $settings.pageZoom
                )
            }
            .settingsAnchor("appearance.zoom")
        }

        WindowStyleSettingsSection(settings: settings)

        SettingsSection(title: "Sidebar", symbol: "sidebar.left") {
            DetailRow(title: "Show sidebar") {
                SettingsToggle(Binding(
                    get: { sidebar.isVisible },
                    set: { sidebar.setVisible($0) }
                ))
            }
            .settingsAnchor("appearance.sidebar")

            RowSeparator()

            DetailRow(title: "Icons only") {
                SettingsToggle(Binding(
                    get: { sidebar.style == .icons },
                    set: { sidebar.setStyle($0 ? .icons : .full) }
                ))
            }
            .settingsAnchor("appearance.sidebarStyle")
        }
    }
}

private struct WindowStyleSettingsSection: View {
    @Bindable var settings: BrowserSettings

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headerGap) {
            SettingsCard {
                DetailRow(title: "Window style", layout: .stacked) {
                    LoomStylePicker(
                        selection: settings.loomStyle,
                        usesWebsiteTint: settings.matchesWebsiteColor,
                        tintsSelectedTab: settings.refractsTabColor
                    ) {
                        settings.loomStyle = $0
                    }
                }
                .settingsAnchor("appearance.windowStyle")

                RowSeparator()

                DetailRow(
                    title: "Website tint",
                    caption: "Use the current website’s color in the toolbar and sidebar."
                ) {
                    SettingsToggle($settings.matchesWebsiteColor)
                }
                .settingsAnchor("appearance.websiteTint")

                RowSeparator()

                DetailRow(
                    title: "Tint selected tab",
                    caption: "The selected tab uses the website icon’s color."
                ) {
                    SettingsToggle($settings.refractsTabColor)
                }
                .settingsAnchor("appearance.refraction")

                if settings.loomStyle == .transparent {
                    RowSeparator()

                    DetailRow(
                        title: "Transparency",
                        caption: "Clear shows more of what’s behind Linen; tinted adds contrast.",
                        layout: .stacked
                    ) {
                        LoomTransparencyControl(opacity: $settings.transparency)
                    }
                    .settingsAnchor("appearance.transparency")
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Text("Choose Standard or Transparent.")
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .animation(Theme.Motion.settle, value: settings.loomStyle)
    }
}
