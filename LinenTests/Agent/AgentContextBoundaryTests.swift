// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The privacy boundary of a task: the agent works only with the pages that
/// were in its context when the user asked - the pages on screen and the tabs
/// attached with @ - plus tabs it opens itself along the way. No tool may
/// name, read, switch to, or close any other tab, and no failure message may
/// leak their titles.
@MainActor
@Suite(.boundedWebViews)
struct AgentContextBoundaryTests {
    private func toolkit(browser: BrowserModel) -> AgentToolkit {
        AgentToolkit(
            browser: browser,
            media: MediaCenter(),
            log: ConversationLog(database: .temporary())
        )
    }

    private func task(on tab: BrowserTab, mentioning mentioned: [UUID] = []) -> AgentTaskContext {
        AgentTaskContext(id: UUID(), tabID: tab.id, mentionedTabIDs: mentioned)
    }

    @Test func switchTabStopsAtTheContextBoundaryWithoutLeakingTitles() {
        let browser = BrowserModel(database: .temporary())
        let secret = browser.newTab()
        secret.title = "Secret research"
        let taskTab = browser.newTab()
        taskTab.title = "Task page"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: taskTab))

        let output = subject.switchTab(matching: "Secret")

        #expect(output.contains("No tab in this conversation matches"))
        #expect(!output.contains("Secret research"))
        #expect(output.contains("Task page"))
        #expect(browser.activeTab === taskTab)
    }

    @Test func closeTabStopsAtTheContextBoundary() {
        let browser = BrowserModel(database: .temporary())
        let secret = browser.newTab()
        secret.title = "Secret research"
        let taskTab = browser.newTab()
        taskTab.title = "Task page"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: taskTab))

        let output = subject.closeTab(matching: "Secret")

        #expect(output.contains("No tab in this conversation matches"))
        #expect(!output.contains("Secret research"))
        #expect(browser.tabs.count == 2)
    }

    /// The user moving to another tab mid-task does not pull that tab into
    /// the conversation - "close the active tab" must not close it.
    @Test func closingTheActiveTabRequiresItToBeInContext() {
        let browser = BrowserModel(database: .temporary())
        let taskTab = browser.newTab()
        taskTab.title = "Task page"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: taskTab))

        let wandered = browser.newTab()
        wandered.title = "Private reading"

        let output = subject.closeTab(matching: nil)

        #expect(output.contains("active tab changed"))
        #expect(browser.tabs.count == 2)
    }

    @Test func switchTabReachesAMentionedTab() {
        let browser = BrowserModel(database: .temporary())
        let mentioned = browser.newTab()
        mentioned.title = "Nike Air Max"
        let taskTab = browser.newTab()
        taskTab.title = "Task page"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: taskTab, mentioning: [mentioned.id]))

        #expect(subject.switchTab(matching: "Nike").contains("Switched"))
        #expect(browser.activeTab === mentioned)
    }

    /// A tab the agent opens during the task joins the conversation: it is
    /// readable in place of the task tab, and the tab the task started on
    /// stays reachable for switching back.
    @Test func aTabTheAgentOpensJoinsTheConversation() async throws {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html("<h1>Fresh page</h1>"),
        ])
        let pageURL = try server.url()
        let browser = BrowserModel(database: .temporary())
        let origin = browser.newTab()
        origin.title = "Origin page"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: origin))

        _ = await subject.newTab(url: pageURL.absoluteString)
        let opened = try #require(browser.activeTab)
        #expect(opened !== origin)

        opened.assistantAccess.persistsAnswers = false
        opened.assistantAccess.pageChanged(url: pageURL)
        opened.assistantAccess.set(.control)

        let read = await subject.readPage()
        #expect(read.contains("Fresh page"))
        #expect(!read.contains("active tab changed"))

        #expect(subject.switchTab(matching: "Origin").contains("Switched"))
        #expect(browser.activeTab === origin)
    }

    /// Context does not accumulate across tasks: a new task starts from what
    /// is on screen, so tabs from an earlier task fall away.
    @Test func aFreshTaskDropsTabsFromAnEarlierOne() async throws {
        let browser = BrowserModel(database: .temporary())
        let first = browser.newTab()
        first.title = "Alpha notes"

        let subject = toolkit(browser: browser)
        subject.beginTask(task(on: first))
        _ = await subject.newTab(url: nil)
        let second = try #require(browser.activeTab)
        #expect(second !== first)

        subject.beginTask(task(on: second))

        let output = subject.switchTab(matching: "Alpha")
        #expect(output.contains("No tab in this conversation matches"))
        #expect(!output.contains("Alpha notes"))
        #expect(browser.activeTab === second)
    }
}
