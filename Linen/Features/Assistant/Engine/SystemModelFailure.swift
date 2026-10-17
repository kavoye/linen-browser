// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import FoundationModels

nonisolated enum SystemModelFailure {
    static func isContextOverflow(_ error: any Error) -> Bool {
        if #available(macOS 27.0, *), let error = error as? LanguageModelError, case .contextSizeExceeded = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = error {
            return true
        }
        let bridged = error as NSError
        return bridged.domain == "com.apple.GenerativeFunctionsFoundation.GenerativeError" && bridged.code == 4_050_000
    }
}
