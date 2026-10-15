// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@Observable
final class VoiceConversationState {
    var session: OpenAIRealtimeConversation?
    var isPresented = false
    var message: String?
    @ObservationIgnored var anchorID: UUID?

    var isActive: Bool {
        session?.isActive == true
    }

    func dismiss() {
        session?.stop()
        isPresented = false
        message = nil
    }
}
