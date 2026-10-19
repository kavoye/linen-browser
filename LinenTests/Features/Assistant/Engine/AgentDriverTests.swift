// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentDriverTests {
    @Test func externalDriversNameThemselvesInConsentAndKeepTheirOwnApprovals() async {
        let policy = AgentActionPolicy(storage: MCPActionGrantStorage())
        let seen = await AgentDriver.external(name: "Claude Code").scope(policy: policy) {
            (AgentActionConsent.externalClientName, AgentActionConsent.scopedPolicy === policy)
        }
        #expect(seen.0 == "Claude Code")
        #expect(seen.1)
    }

    @Test func theAssistantIsNotAnExternalConnection() async {
        let policy = AgentActionPolicy(storage: MCPActionGrantStorage())
        let name = await AgentDriver.assistant.scope(policy: policy) {
            AgentActionConsent.externalClientName
        }
        #expect(name == nil)
        #expect(AgentDriver.assistant.externalName == nil)
    }

    @Test func theToolkitReportsWhoIsDrivingTheTask() {
        let browser = BrowserModel(database: .temporary())
        let tab = browser.newTab()
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: ConversationLog(database: .temporary()))
        #expect(toolkit.driver == .assistant)

        let task = AgentTaskContext(id: UUID(), tabID: tab.id, driver: .external(name: "Claude Code"))
        toolkit.beginTask(task)
        #expect(toolkit.driver == .external(name: "Claude Code"))
        toolkit.finishTask(task)
        #expect(toolkit.driver == .assistant)
    }
}
