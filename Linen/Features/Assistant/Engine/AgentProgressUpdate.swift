// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct AgentProgressUpdate: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let text: String
    let afterStepCount: Int
}
