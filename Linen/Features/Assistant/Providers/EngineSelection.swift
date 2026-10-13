// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class EngineSelection {
    var selectedProvider = ProviderCatalog.openAI
    var selectedModel = ""
    var selectedEffort: LLMSettings.ReasoningEffort = .low
    var supportsReasoningEffort = false

    var activeProvider: Provider?
    var activeNotice: String?
    var isUsingSelectedProvider = true
}
