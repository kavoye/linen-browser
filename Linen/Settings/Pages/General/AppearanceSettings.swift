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
                caption: "Set the default zoom for websites. You can also zoom individual tabs."
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

        WindowStyleSettingsSection(settings: settings, sidebar: sidebar)
    }
}

private struct WindowStyleSettingsSection: View {
    @Bindable var settings: BrowserSettings
    let sidebar: SidebarLayout

    private static let standardAnchors = [
        "appearance.background", "appearance.transparency", "appearance.websiteTint",
        "appearance.refraction", "appearance.sidebar", "appearance.solidSidePanel",
    ]

    private static let minimalAnchors = ["appearance.minimalBar", "appearance.minimalBarAutoHide"]

    var body: some View {
        SettingsCard {
            DetailRow(title: "Window style", layout: .stacked) {
                WindowStylePicker(
                    isMinimal: settings.isMinimal,
                    loomStyle: settings.loomStyle,
                    usesWebsiteTint: settings.matchesWebsiteColor,
                    tintsSelectedTab: settings.refractsTabColor
                ) {
                    settings.isMinimal = $0
                }
            }
            .settingsAnchor(
                "appearance.windowStyle",
                standingInFor: ["appearance.minimal"] + (settings.isMinimal ? Self.standardAnchors : Self.minimalAnchors)
            )

            VStack(spacing: 0) {
                if settings.isMinimal {
                    minimalRows
                        .transition(.opacity)
                } else {
                    standardRows
                        .transition(.opacity)
                }
            }
            .clipped()
        }
        .animation(.smooth(duration: 0.3), value: settings.isMinimal)
    }

    @ViewBuilder private var tabIconsRow: some View {
        RowSeparator()

        DetailRow(
            title: "Show only tab icons",
            caption: "Narrow the list of tabs to website icons."
        ) {
            SettingsToggle(Binding(
                get: { sidebar.style == .icons },
                set: { sidebar.setStyle($0 ? .icons : .full) }
            ))
        }
        .settingsAnchor("appearance.sidebarStyle")
    }

    @ViewBuilder private var minimalRows: some View {
        RowSeparator()

        DetailRow(title: "Bar position") {
            SettingsMenu(
                options: MinimalBarEdge.allCases.map {
                    .init(value: $0, label: String(localized: $0.label))
                },
                selection: $settings.minimalBarEdge
            )
        }
        .settingsAnchor("appearance.minimalBar")

        RowSeparator()

        DetailRow(
            title: "Hide bar automatically",
            caption: "Hide the bar while you scroll. Move the pointer to the edge of the window to show it."
        ) {
            SettingsToggle($settings.hidesMinimalBar)
        }
        .settingsAnchor("appearance.minimalBarAutoHide")

        tabIconsRow
    }

    @ViewBuilder private var standardRows: some View {
        RowSeparator()

        DetailRow(title: "Background") {
            SettingsMenu(
                options: LoomStyle.allCases.map {
                    .init(value: $0, label: String(localized: $0.backgroundLabel))
                },
                selection: $settings.loomStyle
            )
        }
        .settingsAnchor(
            "appearance.background",
            standingInFor: settings.loomStyle == .transparent ? [] : ["appearance.transparency"]
        )

        HeightReveal(isShown: settings.loomStyle == .transparent) {
            RowSeparator()

            DetailRow(
                title: "Transparency",
                caption: "Move left for more transparency or right for more contrast.",
                layout: .stacked
            ) {
                LoomTransparencyControl(opacity: $settings.transparency)
            }
            .settingsAnchor("appearance.transparency")
        }

        RowSeparator()

        DetailRow(
            title: "Website tint",
            caption: "Color the toolbar and sidebar to match the website."
        ) {
            SettingsToggle($settings.matchesWebsiteColor)
        }
        .settingsAnchor("appearance.websiteTint")

        RowSeparator()

        DetailRow(
            title: "Tint selected tab",
            caption: "Color the selected tab to match its website icon."
        ) {
            SettingsToggle($settings.refractsTabColor)
        }
        .settingsAnchor("appearance.refraction")

        RowSeparator()

        DetailRow(
            title: "Show sidebar",
            caption: "When the sidebar is hidden, move the pointer to the left edge of the window to see your tabs."
        ) {
            SettingsToggle(Binding(
                get: { sidebar.isVisible },
                set: { sidebar.setVisible($0) }
            ))
        }
        .settingsAnchor("appearance.sidebar")

        tabIconsRow

        RowSeparator()

        DetailRow(
            title: "Solid side panel",
            caption: "Make the side panel easier to read over busy websites."
        ) {
            SettingsToggle($settings.hasSolidSidePanel)
        }
        .settingsAnchor("appearance.solidSidePanel")
    }
}

private struct HeightReveal<Content: View>: View {
    let isShown: Bool
    @ViewBuilder let content: Content

    @State private var height: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(height: isShown ? height : 0, alignment: .top)
        .clipped()
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        .animation(.smooth(duration: 0.3), value: isShown)
    }
}
