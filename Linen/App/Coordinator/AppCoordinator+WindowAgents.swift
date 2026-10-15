// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    func agentWillLose(_ tab: BrowserTab) {
        let anchorID = browser.anchorID(of: tab.id)
        endVoiceConversation()
        voiceInput.cancel()
        agentTurns.detachTab(tab.id, inAnchor: anchorID)
        tab.setAgentWorking(false)
        statusMessage = nil
        if peek.belongs(to: tab.id) {
            closePeek()
        }
        mediaDock.forget(tab.id)
        if media.controlledTabID == tab.id {
            media.releaseControl()
        }
        conversationLog.saveNow()
    }
}
