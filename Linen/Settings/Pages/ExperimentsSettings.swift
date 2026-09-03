// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ExperimentsSettings: View {
    @Bindable var settings: BrowserSettings

    var body: some View {
        SettingsPageHeader(
            title: "Experiments",
            caption: "Unfinished work you can try. Anything here can change or go away."
        )

        SettingsCard {
            DetailRow(
                title: "Show video in the player",
                caption: "Video from a tab you leave moves into the sidebar player."
            ) {
                SettingsToggle($settings.showsVideoInPlayer)
            }
            .settingsAnchor("experiments.videoInPlayer")
        }
    }
}
