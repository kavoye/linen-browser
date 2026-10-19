// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import os

enum AgentFailure: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        String(localized: "The model returned an empty response. Try again or choose another model.")
    }
}
