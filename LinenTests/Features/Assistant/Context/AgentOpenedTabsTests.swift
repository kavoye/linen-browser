// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct AgentOpenedTabsTests {
    @Test func aTaskShowsInTheTabsItOpens() {
        let log = ConversationLog(database: .temporary())
        let origin = UUID()
        let opened = UUID()
        let task = log.beginTask("Plan a trip", tabID: origin)
        log.noteOpenedTab(opened, taskID: task)

        #expect(log.traces(forTab: origin).map(\.id) == [task])
        #expect(log.traces(forTab: opened).map(\.id) == [task])
        #expect(log.traces(forTab: UUID()).isEmpty)
        #expect(log.latestTrace(forTab: opened) == nil)
    }

    @Test func openedTabsSurviveARelaunch() {
        let database = AppDatabase.temporary()
        let log = ConversationLog(database: database)
        let origin = UUID()
        let opened = UUID()
        let task = log.beginTask("Plan a trip", tabID: origin)
        log.noteOpenedTab(opened, taskID: task)
        log.completeTask(task, response: "Done.")
        log.saveBlocking()

        let reloaded = ConversationLog(database: database)
        #expect(reloaded.traces(forTab: opened).map(\.id) == [task])
    }

    @Test func movingAnOpenedTabMovesItsView() {
        let log = ConversationLog(database: .temporary())
        let origin = UUID()
        let opened = UUID()
        let moved = UUID()
        let task = log.beginTask("Plan a trip", tabID: origin)
        log.noteOpenedTab(opened, taskID: task)
        log.reassign(from: opened, to: moved)

        #expect(log.traces(forTab: moved).map(\.id) == [task])
        #expect(log.traces(forTab: opened).isEmpty)
        #expect(log.traces(forTab: origin).map(\.id) == [task])
    }

    @Test func theAssistantShowsItsWorkInATabItOpens() async throws {
        let browser = BrowserModel(database: .temporary())
        let origin = browser.newTab()
        let log = ConversationLog(database: .temporary())
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log)
        let taskID = log.beginTask("Open a page", tabID: origin.id)
        let task = AgentTaskContext(id: taskID, tabID: origin.id)
        toolkit.beginTask(task)

        _ = await toolkit.newTab(url: nil)
        let opened = try #require(browser.activeTab)
        #expect(opened !== origin)
        #expect(log.traces(forTab: browser.anchorID(of: opened.id)).map(\.id) == [taskID])
        #expect(opened.isAgentWorking)

        toolkit.finishTask(task)
        #expect(!opened.isAgentWorking)
    }

    @Test func aNewTabIsReadAfterItRenders() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<title>Late</title><body><script>setTimeout(() => { document.body.innerHTML = '<p>Rendered later</p>' }, 300)</script></body>"),
        ])
        defer { _ = server }
        let browser = BrowserModel(database: .temporary(), sitePermissions: SitePermissions(storageURL: nil, persists: false))
        let url = try server.url()
        browser.sitePermissions.setAssistantAccess(.control, for: SitePermissions.origin(for: url))
        let origin = browser.newTab()
        let log = ConversationLog(database: .temporary())
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log)
        toolkit.beginTask(AgentTaskContext(id: log.beginTask("Open it", tabID: origin.id), tabID: origin.id))

        let output = await toolkit.newTab(url: url.absoluteString)
        #expect(output.contains("Rendered later"), "\(output)")
    }
}
