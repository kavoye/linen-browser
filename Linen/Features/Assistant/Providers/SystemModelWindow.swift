// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import FoundationModels

nonisolated enum SystemModelWindow {
    static let fallback = 4_096

    static let tokens = window(reported: SystemLanguageModel.default.contextSize)

    static func window(reported: Int) -> Int {
        reported > 0 ? reported : fallback
    }
}
