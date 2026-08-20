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
                caption: "The default for every website. Individual tabs can still be zoomed."
            ) {
                Picker("", selection: $settings.pageZoom) {
                    ForEach(Self.sizes, id: \.self) { size in
                        Text(size, format: .percent.precision(.fractionLength(0)))
                            .tag(size)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .settingsAnchor("appearance.zoom")
        }

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

            RowSeparator()

            DetailRow(
                title: "Show report button",
                caption: "Opens the project’s issue page."
            ) {
                SettingsToggle($settings.showsReportIssueButton)
            }
            .settingsAnchor("appearance.reportIssue")
        }
    }
}
