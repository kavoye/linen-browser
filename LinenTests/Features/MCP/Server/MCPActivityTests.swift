// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP
import Testing

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct MCPActivityTests {
    private struct Fixture {
        let server: HTTPFixtureServer
        let browser: BrowserModel
        let tab: BrowserTab
        let log: ConversationLog
        let session: MCPBrowserSession
    }

    private func fixture(idle: Duration = .seconds(60)) async throws -> Fixture {
        let server = try await HTTPFixtureServer.start(routes: ["/": .html("<title>Fixture</title><p>Shared text</p>")])
        let browser = BrowserModel(database: .temporary(), sitePermissions: SitePermissions(storageURL: nil, persists: false))
        let url = try server.url()
        browser.sitePermissions.setAssistantAccess(.control, for: SitePermissions.origin(for: url))
        let tab = browser.newTab(url: url)
        #expect(await PageSettle.untilIdle(tab.webView))
        let log = ConversationLog(database: .temporary())
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log)
        let session = MCPBrowserSession(browser: browser, available: { true }, approve: { _, _ in true }, toolkit: toolkit, idle: idle)
        session.clientName = "Claude Code"
        return Fixture(server: server, browser: browser, tab: tab, log: log, session: session)
    }

    @Test func externalWorkIsATaskInTheTabsConversation() async throws {
        let subject = try await fixture()
        defer { _ = subject.server }
        _ = try await subject.session.call(name: "readPage", arguments: ["lookingFor": "", "page": ""])
        let trace = try #require(subject.log.traces.last)
        #expect(trace.tabID == subject.browser.anchorID(of: subject.tab.id))
        #expect(!trace.hasUserPrompt)
        #expect(trace.state == .running)
        #expect(trace.steps.map(\.toolName) == ["readPage"])
        #expect(subject.tab.isAgentWorking)
    }

    @Test func disconnectingFinishesTheTaskAndNamesTheClient() async throws {
        let subject = try await fixture()
        defer { _ = subject.server }
        _ = try await subject.session.call(name: "readPage", arguments: ["lookingFor": "", "page": ""])
        subject.session.revoke()
        let trace = try #require(subject.log.traces.last)
        #expect(trace.state == .completed)
        #expect(trace.response.contains("Claude Code"))
        #expect(!subject.tab.isAgentWorking)
    }

    @Test func aPauseEndsTheTaskAndTheNextCallStartsAnother() async throws {
        let subject = try await fixture(idle: .milliseconds(50))
        defer { _ = subject.server }
        _ = try await subject.session.call(name: "readPage", arguments: ["lookingFor": "", "page": ""])
        #expect(await waitUntil { subject.log.traces.last?.state == .completed })
        _ = try await subject.session.call(name: "listTabs", arguments: [:])
        #expect(subject.log.traces.count == 2)
        #expect(subject.log.traces.last?.steps.map(\.toolName) == ["listTabs"])
    }

    @Test func theTaskAlsoShowsInTheTabTheClientOpens() async throws {
        let subject = try await fixture()
        defer { _ = subject.server }
        let opened = try await subject.session.call(name: "newTab", arguments: ["url": .string(try subject.server.url().absoluteString)])
        #expect(opened.isError == false)
        let newTab = try #require(subject.browser.activeTab)
        #expect(newTab !== subject.tab)
        let trace = try #require(subject.log.traces.last)
        #expect(subject.log.traces.count == 1)
        #expect(trace.tabID == subject.browser.anchorID(of: subject.tab.id))
        #expect(subject.log.traces(forTab: subject.browser.anchorID(of: newTab.id)).map(\.id) == [trace.id])
        #expect(newTab.isAgentWorking)
        _ = try await subject.session.call(name: "listTabs", arguments: [:])
        #expect(subject.log.traces.count == 1)
        subject.session.revoke()
        #expect(!newTab.isAgentWorking)
        #expect(!subject.tab.isAgentWorking)
    }

    @Test func verifiedClientsShowTheirBrand() {
        #expect(MCPBrowserSession.providerID(for: MCPClientIdentity(name: "Claude Code", path: "/x", developer: "Anthropic PBC")) == "anthropic")
        #expect(MCPBrowserSession.providerID(for: MCPClientIdentity(name: "Codex", path: "/x", developer: "OpenAI, L.L.C.")) == "openai")
        #expect(MCPBrowserSession.providerID(for: MCPClientIdentity(name: "codex", path: "/x", developer: nil)) == nil)
        #expect(MCPBrowserSession.providerID(for: nil) == nil)
    }
}
