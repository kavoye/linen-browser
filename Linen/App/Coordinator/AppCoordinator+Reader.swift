// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AppCoordinator {
    var readerTab: BrowserTab? {
        guard !isShowingSettings, shownPeek == nil, browser.activeSplit == nil else { return nil }
        return browser.activeTab
    }

    func toggleReader() {
        readerTab?.reader.toggle()
    }

    func connectReaderListener() {
        readerListener.onWillStart = { [weak self] in
            self?.stopAgentSpeech()
        }
    }

    func agentSpeechChanged(_ speaking: Bool) {
        if speaking {
            readerListener.stop()
        }
    }
}
