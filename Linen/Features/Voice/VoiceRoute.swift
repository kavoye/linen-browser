// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class VoiceRoute {
    private(set) var openAIProviderID: String?
    private(set) var dictatesWithOpenAI = false
    private(set) var readsWithOpenAI = false
    @ObservationIgnored private var identity: String?
    @ObservationIgnored var preparation: Task<Void, Never>?

    var canUseOpenAI: Bool {
        openAIProviderID != nil
    }

    func update(openAIProviderID: String?, wantsOpenAIDictation: Bool, wantsOpenAIReading: Bool) {
        self.openAIProviderID = openAIProviderID
        dictatesWithOpenAI = canUseOpenAI && wantsOpenAIDictation
        readsWithOpenAI = canUseOpenAI && wantsOpenAIReading
    }

    func adopt(_ identity: String) -> Bool {
        guard self.identity != identity else { return false }
        self.identity = identity
        return true
    }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
    }
}
