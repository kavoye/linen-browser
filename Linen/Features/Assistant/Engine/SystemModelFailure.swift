// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import FoundationModels

nonisolated enum SystemModelFailure {
    static func isContextOverflow(_ error: any Error) -> Bool {
        guard let error = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = error {
            return true
        }
        return false
    }
}
