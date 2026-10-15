// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

#if DEBUG
import AppKit
import os

enum SpaceBench {
    static let isOn = ProcessInfo.processInfo.environment["LINEN_SPACE_BENCH"] != nil

    @MainActor
    static func run(_ coordinator: AppCoordinator) {
        guard isOn else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let browser = coordinator.browser
            let profileID = coordinator.profiles.current.id
            var spaces = coordinator.spaceStore.spaces(for: profileID)
            if spaces.count < 2 {
                coordinator.spaceStore.add(name: "Bench", symbol: "flask", color: .blue, profileID: profileID)
                coordinator.refreshSpaces()
                spaces = coordinator.spaceStore.spaces(for: profileID)
                let items = browser.sidebarItems
                browser.move(Array(items.suffix(items.count / 2)), toSpace: spaces[1].id)
            }
            Pipeline.log.notice("space bench: begin")
            let swipes = ProcessInfo.processInfo.environment["LINEN_BENCH_SWIPE"] != nil
            for index in 0..<8 {
                if swipes {
                    let forward = index % 2 == 0
                    for step in 1...30 {
                        coordinator.spaceSlider.drag(to: CGFloat(step) * 7 * (forward ? -1 : 1))
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    coordinator.spaceSlider.endSwipe(travel: 210 * (forward ? -1 : 1), velocity: 440 * (forward ? -1 : 1))
                } else {
                    coordinator.switchSpace(to: spaces[(index + 1) % 2])
                }
                try? await Task.sleep(for: .milliseconds(1200))
            }
            Pipeline.log.notice("space bench: end")
            NSApp.terminate(nil)
        }
    }

}

#endif
