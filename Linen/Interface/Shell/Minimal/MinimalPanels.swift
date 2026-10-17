// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct IslandMoreMenu: View {
    let coordinator: AppCoordinator
    @Binding var isPresented: Bool

    private func run(_ action: @escaping () -> Void) -> () -> Void {
        {
            isPresented = false
            action()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ProfileMenuRows(coordinator: coordinator, isPresented: $isPresented)

            PopoverMenuDivider()

            PopoverMenuRow(symbol: "arrow.down", title: String(localized: "Downloads…"), shortcut: "⌥⌘L", action: run { coordinator.showDownloads() })
            PopoverMenuRow(symbol: "clock", title: String(localized: "History…"), shortcut: "⌘Y", action: run { coordinator.showHistory() })
            PopoverMenuRow(symbol: "gearshape", title: String(localized: "Settings…"), shortcut: "⌘,", action: run { coordinator.openSettings() })
        }
        .padding(PopoverMenuRow<EmptyView>.inset)
        .frame(width: PopoverMenuRow<EmptyView>.width)
        .chromePopoverAppearance()
    }
}
