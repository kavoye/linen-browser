// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
final class ComputerWorkflowFixture {
    private let server: HTTPFixtureServer
    let browser: BrowserModel
    let log: ConversationLog
    let toolkit: AgentToolkit
    let tab: BrowserTab
    let window: NSWindow
    let folder: URL
    let reply = AgentReplyModel()
    private var agent: AnyLanguageModelAgent?

    var completed: Bool {
        log.latestTrace(forTab: tab.id)?.diagnostics.events.last(where: { $0.kind == "terminal" })?.values["status"] == "completed"
    }

    init() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("linen-computer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        server = try await HTTPFixtureServer.start(routes: ["/": .html("""
            <!doctype html><body style="margin:0;font-family:system-ui;background:white;color:black">
            <h1 style="margin:20px">Computer workflow fixture</h1>
            <button style="position:absolute;left:20px;top:90px;width:140px;height:44px"
                onclick="window.chosen=(window.chosen||0)+1;document.querySelector('#status').textContent='Selected'">Choose</button>
            <label style="position:absolute;left:20px;top:160px">Query <input aria-label="Query" id="query" style="width:220px;height:30px"></label>
            <p id="status" style="position:absolute;left:20px;top:230px">Not selected</p>
            </body>
            """),
        ])
        let database = AppDatabase.temporary()
        let permissions = SitePermissions(storageURL: folder.appendingPathComponent("permissions.json"))
        let store = WKWebsiteDataStore.nonPersistent()
        browser = BrowserModel(database: database, sitePermissions: permissions, webViewFactory: {
            let config = WebViewPool.makeConfiguration()
            config.websiteDataStore = store
            return WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: config)
        })
        log = ConversationLog(database: database)
        toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log)
        tab = browser.newTab(url: URL(string: "about:blank")!)
        window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 500, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.webView
        window.orderBack(nil)
        let base = try server.url()
        tab.load(base)
        guard await waitForObservation({ self.tab.committedURL == base && !self.tab.isLoading }),
              (try? await tab.webView.evaluateJavaScript("!!document.querySelector('#query')")) as? Bool == true else {
            close()
            throw HarnessFixtureFailure()
        }
        tab.assistantAccess.persistsAnswers = false
        tab.assistantAccess.pageChanged(url: tab.webView.url ?? base)
        tab.assistantAccess.set(.control)
    }

    @discardableResult
    func run(client: OpenAIResponsesClient, prompt: String) async -> UUID {
        let agent = AnyLanguageModelAgent(name: "computer fixture", modelID: client.model, executionPolicy: .init(maxModelRequests: 6),
            toolOverrides: [], openAI: client, model: HarnessScript([]), options: GenerationOptions(),
            budget: ContextBudget(windowTokens: 128_000, responseTokens: 2_048, inputTokens: 120_000,
                toolSchemaTokens: 0, instructionTier: .compact, toolTier: .full, toolOutput: .standard, retainedExchanges: 12, retainedToolRounds: 10),
            toolkit: toolkit, log: log)
        self.agent = agent
        let id = log.beginTask(prompt, tabID: tab.id)
        await agent.run(utterance: prompt, task: .init(id: id, tabID: tab.id), into: reply, speech: HarnessSpeech())
        return id
    }

    func close() {
        agent?.discardAllSessions()
        tab.webView.stopLoading()
        window.contentView = nil
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }
}
