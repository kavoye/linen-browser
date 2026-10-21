// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct AgentTurnState {
    var startedAt = Date()
    var askedUser = false
    var preferenceReminded = false
    var refusedActions = 0
    var lastReads: [String: String] = [:]
    var repeatedRead = false
    var lastMiss: String?
    var withheldTools: Set<String> = []
    var checkedAnswers = 0
    var memoryUpdates: [AgentMemoryUpdate] = []
    var userWords: [String] = []

    mutating func begin(isContinuation: Bool) {
        let startedAt = isContinuation ? startedAt : Date()
        self = AgentTurnState()
        self.startedAt = startedAt
    }
}
