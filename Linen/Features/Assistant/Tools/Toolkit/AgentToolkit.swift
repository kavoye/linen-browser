// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
final class AgentToolkit {
    let browser: BrowserModel
    let media: MediaCenter
    let log: ConversationLog
    let services: Services
    private let questions: AgentQuestionModel?
    let scope: AgentTabScope
    let safety: AgentPageSafety
    let search: AgentWebSearch
    var turn = AgentTurnState()
    private(set) var lastToolFailed = false
    var requestConstraints = AgentRequestConstraints.none

    typealias VisiblePageAuthorization = AgentPageSafety.Authorization

    private var task: AgentTaskContext? {
        scope.task
    }
    var driver: AgentDriver {
        task?.driver ?? .assistant
    }
    var fileSelection: ((WKOpenPanelParameters) async -> [URL]?)? {
        services.chooseFiles
    }

    func embeddedAccess(for url: URL, in view: WKWebView) -> TabAssistantAccessCenter? {
        safety.embeddedAccess(for: url, in: view)
    }

    func taskDownloads(in view: WKWebView) -> [DownloadManager.Item] {
        guard let tab = scope.onScreenTab(for: view) ?? scope.mentionedTab(for: view) else { return [] }
        let origin = SitePermissions.origin(for: view.url)
        return browser.downloads.items.filter {
            $0.sourceTabID == tab.id && $0.started >= turn.startedAt &&
                $0.sourceOrigin == origin
        }
    }

    func rejectTool(name: String, reason: String) -> String {
        let step = beginTool(name: name)
        completeTool(step, failed: true)
        return reason
    }

    func resetToolOutcome() {
        lastToolFailed = false
    }

    var outputBudget = ContextBudget.ToolOutputBudget.standard
    @TaskLocal static var requestedPage: String?

    init(
        browser: BrowserModel,
        media: MediaCenter,
        log: ConversationLog,
        questions: AgentQuestionModel? = nil,
        services: Services = .live
    ) {
        self.browser = browser
        self.media = media
        self.log = log
        self.services = services
        self.questions = questions
        scope = AgentTabScope(browser: browser)
        safety = AgentPageSafety(scope: scope)
        search = AgentWebSearch(search: services.search)
    }

    func withPageContext(
        page: String?, observationID: String?,
        operation: @MainActor () async -> String
    ) async -> String {
        await Self.$requestedPage.withValue(page) {
            await PageDriver.$expectedObservation.withValue(observationID) {
                await PageDriver.$outputBudget.withValue(outputBudget.driverBudget) {
                    await operation()
                }
            }
        }
    }

    private(set) var pendingScreenshot: Data?
    var computerObservation: PageComputerFrame?

    func setComputerScreenshot(_ data: Data?) {
        pendingScreenshot = data
    }

    func takePendingScreenshot() -> Data? {
        defer { pendingScreenshot = nil }
        return pendingScreenshot
    }

    func pageOperation(
        name: String, readOnly: Bool = false,
        operation: (WKWebView) async -> String
    ) async -> String {
        let step = beginTool(name: name)
        if let cancelled = cancellationOutput(for: step) {
            pendingScreenshot = nil
            return cancelled
        }
        guard let view = targetWebView else {
            completeTool(step, failed: true)
            return "No matching page is open."
        }
        let capability: AssistantPageCapability = readOnly ? .read : .control
        let access = await authorize(capability, in: view)
        if let denial = access.denial {
            completeTool(step, failed: true)
            return denial
        }
        let output = await guardedPageOperation(in: view, authorization: access.authorization, capability: capability) {
            await operation(view)
        }
        if let cancelled = cancellationOutput(for: step) {
            pendingScreenshot = nil
            return cancelled
        }
        if let denial = postflightDenial(for: access.authorization, in: view) {
            pendingScreenshot = nil
            completeTool(step, failed: true)
            return denial
        }
        remember(links: links(in: output))
        let succeeded = [
            "CONTROL:", "Condition met.", "Clicked", "Typed", "Selected", "Set checked", "Checked state",
            "Screenshot captured.", "Scrolled", "Already at", "Dispatched hover", "Sent ",
        ].contains { output.hasPrefix($0) }
        completeTool(step, failed: !succeeded)
        return fencedPageOutput(output)
    }

    func screenshotPage() async -> String {
        pendingScreenshot = nil
        computerObservation = nil
        return await pageOperation(name: "screenshotPage", readOnly: true) { view in
            guard let (frame, data) = try? await PageDriver.computerFrame(in: view) else {
                computerObservation = nil
                return "Screenshot unavailable. The page may contain filled sensitive fields. Use readPage for redacted text."
            }
            computerObservation = frame
            pendingScreenshot = data
            return "Screenshot captured. Use its pixel coordinates with movePointer or clickAtPoint.\n"
                + (await PageDriver.snapshot(view, viewportOnly: true))
        }
    }

    func guardedPageOperation(
        in view: WKWebView, authorization: VisiblePageAuthorization?, capability: AssistantPageCapability,
        operation: () async -> String
    ) async -> String {
        let scope = PageAutomationGuard(documentURL: view.url?.absoluteString ?? "about:blank", snapshot: nil) { [weak self, weak view] in
            guard let self, let view, self.postflightDenial(for: authorization, in: view) == nil else { return false }
            guard let authorization else { return false }
            guard let tab = self.browser.tabs.first(where: { $0.id == authorization.tabID }) else { return false }
            let policy = tab.assistantAccess.effectivePolicy
            return policy.allows(capability) && (capability == .read || self.scope.onScreenTab(for: view) === tab)
        }
        return await PageAutomationGuard.$current.withValue(scope) {
            await PageDriver.$outputBudget.withValue(outputBudget.driverBudget) { await operation() }
        }
    }

    // MARK: - Task lifecycle

    func beginTask(_ task: AgentTaskContext) {
        turn.begin(isContinuation: task.isContinuation)
        computerObservation = nil
        safety.reset()
        search.reset()
        scope.begin(task)
    }

    func finishTask(_ completedTask: AgentTaskContext) {
        guard let opened = scope.finish(completedTask) else { return }
        for id in opened {
            browser.setAgentWorking(false, inAnchor: browser.anchorID(of: id))
        }
        computerObservation = nil
        search.reset()
    }

    // MARK: - Behaviour

    // MARK: - Helpers

    var browserContext: BrowserProfileContext {
        browser.context
    }

    var targetWebView: WKWebView? {
        if let page = Self.requestedPage, !page.isEmpty {
            return readableSurface(named: page)?.webView
        }
        return browser.activeTab?.webView
    }

    var visibleTaskTab: BrowserTab? {
        scope.visibleTaskTab
    }

    var onScreenTabs: [BrowserTab] {
        scope.onScreenTabs
    }

    var mentionedTabs: [BrowserTab] {
        scope.mentionedTabs
    }

    func pageIdentifier(for view: WKWebView) -> String {
        scope.pageIdentifier(for: view)
    }

    func pageSurface(named reference: String) -> WKWebView? {
        scope.pageSurface(named: reference)
    }

    func authorize(
        _ capability: AssistantPageCapability,
        in webView: WKWebView,
        requiresTaskTab: Bool = true
    ) async -> (authorization: VisiblePageAuthorization?, denial: String?) {
        await safety.authorize(capability, in: webView, requiresTaskTab: requiresTaskTab)
    }

    func postflightDenial(for authorization: VisiblePageAuthorization?, in webView: WKWebView) -> String? {
        safety.postflightDenial(for: authorization, in: webView)
    }

    nonisolated static func untrusted(_ pageText: String) -> String {
        let escaped = pageText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <page-content untrusted="true">
        \(escaped)
        </page-content>
        """
    }

    func fencedPageOutput(_ pageText: String) -> String {
        safety.fence(pageText)
    }

    func outboundDenial(for url: URL) -> String? {
        safety.outboundDenial(for: url)
    }

    func remember(links: [ConversationLog.ActivityLink]) {
        safety.remember(links)
    }

    func beginTool(name: String) -> UUID? {
        guard let task else { return nil }
        return log.beginTool(taskID: task.id, name: name)
    }

    func completeTool(_ stepID: UUID?, failed: Bool = false) {
        lastToolFailed = failed
        guard let task else { return }
        log.completeTool(taskID: task.id, stepID: stepID, failed: failed)
    }

    func cancellationOutput(for stepID: UUID?) -> String? {
        guard Task.isCancelled else { return nil }
        let output = String(localized: "Canceled.")
        completeTool(stepID, failed: true)
        return output
    }
}

extension AgentToolkit {
    func askUser(_ asked: [(question: String, options: [String])]) async -> String {
        turn.askedUser = true
        let put = asked.compactMap { entry -> AgentQuestionModel.Question? in
            let text = entry.question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return AgentQuestionModel.Question(text: text, options: entry.options)
        }
        guard !put.isEmpty, let questions else {
            return "No one is there to answer. Carry on with what you have."
        }
        let step = beginTool(name: "askUser")
        if let output = cancellationOutput(for: step) {
            return output
        }
        let answers = await questions.put(put, inAnchor: task?.anchorID)
        let trimmed = answers.trimmingCharacters(in: .whitespacesAndNewlines)
        turn.userWords.append(trimmed)
        guard !trimmed.isEmpty else {
            let output = "Nothing was answered. Carry on with what you have."
            completeTool(step, failed: true)
            return output
        }
        completeTool(step)
        return trimmed
    }
}

extension AgentToolkit {
    func links(in observation: String) -> [ConversationLog.ActivityLink] {
        PageDriver.listedLinks(in: observation).map { link in
            let title = link.label.isEmpty ? (link.url.host() ?? link.url.absoluteString) : link.label
            return ConversationLog.ActivityLink(title: title, url: link.url)
        }
    }
}

extension AgentToolkit {
    func continueTask(_ continued: AgentTaskContext) {
        scope.continueTask(continued)
    }

    func followActiveTab() -> AgentTaskContext? {
        scope.followActiveTab()
    }
}
