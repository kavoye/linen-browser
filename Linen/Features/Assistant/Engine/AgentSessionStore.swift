// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

@MainActor
final class AgentSessionStore {
    private var sessions: [UUID: LanguageModelSession] = [:]
    private var discarded = RecentIDs()
    private var prewarmed: LanguageModelSession?

    subscript(tabID: UUID) -> LanguageModelSession? {
        sessions[tabID]
    }

    func isDiscarded(_ tabID: UUID) -> Bool {
        discarded.contains(tabID)
    }

    func store(_ session: LanguageModelSession, for tabID: UUID) {
        sessions[tabID] = session
    }

    func keep(_ session: LanguageModelSession, for tabID: UUID) {
        guard !discarded.contains(tabID) else { return }
        sessions[tabID] = session
    }

    func discard(_ tabID: UUID) {
        discarded.insert(tabID)
        sessions.removeValue(forKey: tabID)
    }

    func reset(_ tabID: UUID) {
        sessions.removeValue(forKey: tabID)
    }

    func removeAll() {
        sessions.removeAll()
        discarded = RecentIDs()
        prewarmed = nil
    }

    func transfer(from tabID: UUID, to newTabID: UUID) {
        guard tabID != newTabID,
              sessions[newTabID] == nil,
              !discarded.contains(newTabID),
              let session = sessions.removeValue(forKey: tabID)
        else { return }
        sessions[newTabID] = session
    }

    func prewarm(_ make: () -> LanguageModelSession) {
        guard prewarmed == nil else { return }
        let session = make()
        session.prewarm()
        prewarmed = session
    }

    func takePrewarmed() -> LanguageModelSession? {
        defer { prewarmed = nil }
        return prewarmed
    }
}
