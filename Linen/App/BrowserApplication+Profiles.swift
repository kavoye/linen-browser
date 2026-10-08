// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension BrowserApplication {
    /// Release every window before removing a profile's website and disk data.
    func prepareToRemove(profile: Profile) async {
        guard !profile.isOriginal else { return }
        BrowserProfileContext.existing(for: profile.id)?.pageWatches.shutDown()
        let affected = windows.filter { $0.profiles.current.id == profile.id }
        for coordinator in affected {
            coordinator.closeWindow()
            if windows.contains(where: { $0 === coordinator }) {
                coordinator.windowDidClose()
            }
        }
        forgetProfile(profile.id)
    }
}
