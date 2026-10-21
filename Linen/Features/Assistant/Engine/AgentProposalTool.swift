// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation

struct AgentProposalBoundary: Error {}

nonisolated struct AgentProposalTool: Tool {
    typealias Arguments = GeneratedContent
    let name: String
    let description: String
    let parameters: GenerationSchema

    func call(arguments: GeneratedContent) async throws -> String {
        if let observer = AgentToolProposalScope.current {
            await observer.propose(name: name, arguments: arguments)
        }
        throw AgentProposalBoundary()
    }
}
