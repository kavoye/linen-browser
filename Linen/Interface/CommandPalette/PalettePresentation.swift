// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Observation

@Observable
final class PalettePresentation {
    private(set) var isOpen = false
    private(set) var isNewTab = false
    private(set) var token = 0
    private(set) var seed: String?

    @discardableResult
    func open(seed: String? = nil) -> Bool {
        guard !isOpen else { return false }
        self.seed = seed?.isEmpty == false ? seed : nil
        token += 1
        isOpen = true
        return true
    }

    func markNewTab() {
        isNewTab = true
    }

    func close() {
        isOpen = false
        isNewTab = false
    }
}
