// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP
import Testing
import WebKit

@testable import Linen

@MainActor
@Suite(.boundedWebViews)
struct MCPPrivacyTests {
    private static let html = """
        <!doctype html><title>Shared fixture</title>
        <p>Visible shared text</p>
        <input aria-label="Search"><input aria-label="Password" type="password" value="hidden-secret">
        <button onclick="document.body.dataset.clicked='yes'">Ordinary action</button>
        <a href="/next">Next page</a>
        """

    private func fixture(access: AssistantAccessPolicy = .control) async throws -> (HTTPFixtureServer, BrowserModel, BrowserTab) {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html(Self.html), "/next": .html("<title>Next</title><p>Next page</p>"),
        ])
        let browser = BrowserModel(database: .temporary(), sitePermissions: SitePermissions(storageURL: nil, persists: false))
        let url = try server.url()
        browser.sitePermissions.setAssistantAccess(access, for: SitePermissions.origin(for: url))
        let tab = browser.newTab(url: url)
        #expect(await PageSettle.untilIdle(tab.webView))
        return (server, browser, tab)
    }

    private func session(
        _ browser: BrowserModel, approve: @escaping (String, MCPClientIdentity?) async -> Bool = { _, _ in true }
    ) -> MCPBrowserSession {
        MCPBrowserSession(browser: browser, available: { true }, approve: approve)
    }

    private func text(_ result: CallTool.Result) -> String {
        result.content.compactMap {
            if case .text(let text, _, _) = $0 {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func call(_ session: MCPBrowserSession, _ name: String, _ arguments: [String: Value] = [:]) async throws -> CallTool.Result {
        try await session.call(name: name, arguments: arguments)
    }

    private func observationID(in result: CallTool.Result) throws -> String {
        let match = try #require(text(result).firstMatch(of: /observationID: (\S+)/))
        return String(match.1)
    }

    @Test func externalClientsSeeTheAssistantsToolsExceptAskingTheUser() {
        let names = Set(MCPToolCatalog.tools().map(\.name))
        #expect(names == Set(agentToolTypes.map { $0.toolName }).subtracting([AskUserTool.toolName]))
        #expect(names.contains("searchWeb"))
        #expect(!names.contains("requestAccess"))
    }

    @Test func toolSchemasComeFromTheAssistantsArguments() throws {
        let tool = try #require(MCPToolCatalog.tools().first { $0.name == "fillFields" })
        guard case .object(let schema) = tool.inputSchema, case .object(let properties)? = schema["properties"] else {
            Issue.record("fillFields has no object schema")
            return
        }
        #expect(properties["fields"] != nil)
        #expect(properties["observationID"] != nil)
        #expect(tool.description == FillFieldsTool.toolDescription)
    }

    @Test func anApprovedClientReadsTheActivePageWithoutSharingTabs() async throws {
        let (server, browser, _) = try await fixture()
        defer { _ = server }
        let read = try await call(session(browser), "readPage", ["lookingFor": "", "page": ""])
        #expect(read.isError == false, "\(text(read))")
        #expect(text(read).contains("Visible shared text"))
        #expect(!text(read).contains("hidden-secret"))
    }

    @Test func actionsUseTheAssistantsObservationRules() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        let first = try observationID(in: try await call(subject, "readPage", ["lookingFor": "", "page": ""]))
        let click = try await call(subject, "clickOnPage", ["observationID": .string(first), "ref": 3, "label": ""])
        #expect(click.isError == false, "\(text(click))")
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.clicked") as? String == "yes")
        let stale = try await call(subject, "clickOnPage", ["observationID": "stale", "ref": 3, "label": ""])
        #expect(stale.isError == true)
    }

    @Test func passwordFieldsStayBlocked() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        let first = try observationID(in: try await call(subject, "readPage", ["lookingFor": "", "page": ""]))
        let typed = try await call(subject, "typeOnPage", [
            "observationID": .string(first), "ref": 2, "field": "", "text": "never-written", "submit": false,
        ])
        #expect(typed.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.querySelector('[type=password]').value") as? String == "hidden-secret")
    }

    @Test func siteAssistantAccessAppliesExactlyAsInTheBrowser() async throws {
        let (server, browser, tab) = try await fixture(access: .readOnly)
        defer { _ = server }
        let subject = session(browser)
        let first = try observationID(in: try await call(subject, "readPage", ["lookingFor": "", "page": ""]))
        let click = try await call(subject, "clickOnPage", ["observationID": .string(first), "ref": 3, "label": ""])
        #expect(click.isError == true)
        #expect(text(click).contains(tab.assistantAccess.denialMessage(for: .control)))

        tab.assistantAccess.set(.deny)
        let read = try await call(subject, "readPage", ["lookingFor": "", "page": ""])
        #expect(read.isError == true)
        #expect(!text(read).contains("Visible shared text"))
    }

    @Test func newTabsOpenWithoutAnExtraPrompt() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        let opened = try await call(subject, "newTab", ["url": .string(try server.url("/next").absoluteString)])
        #expect(opened.isError == false, "\(text(opened))")
        #expect(text(opened).contains("Next page"))
        #expect(browser.tabs.count == 2)
        #expect(browser.activeTab !== tab)
    }

    @Test func aRefusedConnectionCannotUseAnyToolAndIsAskedOnce() async throws {
        let (server, browser, _) = try await fixture()
        defer { _ = server }
        var approvals = 0
        let subject = session(browser) { _, _ in
            approvals += 1
            return false
        }
        let first = try await call(subject, "readPage", ["lookingFor": "", "page": ""])
        #expect(first.isError == true)
        #expect(text(first).contains("didn’t allow"))
        #expect(!text(first).contains("Visible shared text"))
        #expect(try await call(subject, "listTabs").isError == true)
        #expect(approvals == 1)
    }

    @Test func anAllowedConnectionIsAskedOnlyOnce() async throws {
        let (server, browser, _) = try await fixture()
        defer { _ = server }
        var approvals = 0
        let subject = session(browser) { _, _ in
            approvals += 1
            return true
        }
        #expect(try await call(subject, "listTabs").isError == false)
        #expect(try await call(subject, "readPage", ["lookingFor": "", "page": ""]).isError == false)
        #expect(approvals == 1)
    }

    @Test func badArgumentsFailTheCallInsteadOfTheConnection() async throws {
        let (server, browser, _) = try await fixture()
        defer { _ = server }
        let result = try await call(session(browser), "readPage", ["lookingFor": 7])
        #expect(result.isError == true)
        await #expect(throws: MCPError.self) {
            _ = try await self.call(self.session(browser), "requestAccess")
        }
    }

    @Test func privateWindowsAreNeverDriven() {
        let browser = BrowserModel(database: .temporary())
        browser.opensPrivately = true
        let server = BrowserMCPServer(browser: browser, available: { true })
        #expect(server.makeSessionForConnection() == nil)
    }

    @Test func pageWorldScriptsCannotReplaceTheDriver() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        _ = try await tab.webView.evaluateJavaScript("window.__linen = { pageText: () => 'forged-content', collect: () => [] };")
        let read = try await call(session(browser), "readPage", ["lookingFor": "", "page": ""])
        #expect(text(read).contains("Visible shared text"))
        #expect(!text(read).contains("forged-content"))
    }
}
