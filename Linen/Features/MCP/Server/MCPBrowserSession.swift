// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import MCP
import Observation

@MainActor
@Observable
final class MCPBrowserSession: Identifiable {
    let id = UUID()
    var clientName = String(localized: "External Connection")
    var identity: MCPClientIdentity?
    private(set) var isConnected = true
    private(set) var lastTool = ""
    private(set) var completedCalls = 0
    @ObservationIgnored private let browser: BrowserModel
    @ObservationIgnored private let available: () -> Bool
    @ObservationIgnored private let approve: (String, MCPClientIdentity?) async -> Bool
    @ObservationIgnored private let toolkit: AgentToolkit
    @ObservationIgnored private let tools: [String: any AnyLanguageModel.Tool]
    @ObservationIgnored private let actionPolicy = AgentActionPolicy(storage: MCPActionGrantStorage())
    @ObservationIgnored private var approval: Bool?
    @ObservationIgnored private var task: AgentTaskContext?
    @ObservationIgnored private var trace: (id: UUID, anchorID: UUID)?
    @ObservationIgnored private var idleFinish: Task<Void, Never>?
    @ObservationIgnored private let idle: Duration
    @ObservationIgnored private var busy = false

    var displayName: String {
        identity?.name ?? clientName
    }

    var lastActionTitle: String? {
        guard !lastTool.isEmpty else { return nil }
        return AgentToolCatalog.all.first { $0.id == lastTool }.map { String(localized: $0.title) }
    }

    init(
        browser: BrowserModel,
        available: @escaping () -> Bool,
        approve: @escaping (String, MCPClientIdentity?) async -> Bool = MCPAccessConsent.approve,
        toolkit: AgentToolkit? = nil,
        idle: Duration = .seconds(20)
    ) {
        self.browser = browser
        self.idle = idle
        self.available = available
        self.approve = approve
        let toolkit = toolkit ?? AgentToolkit(browser: browser, media: MediaCenter(), log: ConversationLog(database: .temporary()))
        self.toolkit = toolkit
        tools = Dictionary(
            makeAgentTools(toolkit: toolkit).filter { MCPToolCatalog.names.contains($0.name) }.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func isBound(to browser: BrowserModel) -> Bool {
        self.browser === browser
    }

    func revoke() {
        isConnected = false
        finishTrace()
        if let task {
            toolkit.finishTask(task)
        }
        task = nil
        actionPolicy.revokeAll()
    }

    func call(name: String, arguments: [String: Value]) async throws -> CallTool.Result {
        guard let tool = tools[name] else { throw MCPError.invalidParams("Unknown tool.") }
        guard isConnected, available(), !Task.isCancelled else {
            return failure("Linen is unavailable. Retry after leaving private browsing or after Linen’s assistant finishes.")
        }
        guard !busy else { return failure("Another operation is running. Wait for its result.") }
        busy = true
        lastTool = name
        idleFinish?.cancel()
        defer {
            busy = false
            completedCalls += 1
            scheduleIdleFinish()
        }
        if approval == nil {
            approval = await approve(displayName, identity)
        }
        guard approval == true, isConnected, available(), !Task.isCancelled else {
            return failure("The user didn’t allow this connection in Linen. Reconnecting the client asks them again.")
        }
        guard let content = Self.content(from: arguments) else {
            return failure("The arguments for \(name) don’t match its schema.")
        }
        prepareTask()
        return await AgentDriver.external(name: displayName).scope(policy: actionPolicy) {
            toolkit.resetToolOutcome()
            let output: String
            do {
                output = AnyLanguageModelAgent.text(in: try await AnyLanguageModelAgent.execute(tool, arguments: content))
            } catch {
                _ = toolkit.takePendingScreenshot()
                return failure("The arguments for \(name) don’t match its schema.")
            }
            var blocks: [MCP.Tool.Content] = [.text(text: output, annotations: nil, _meta: nil)]
            if let image = toolkit.takePendingScreenshot() {
                blocks.append(.image(data: image.base64EncodedString(), mimeType: "image/jpeg", annotations: nil, _meta: nil))
            }
            return CallTool.Result(content: blocks, isError: toolkit.lastToolFailed)
        }
    }

    static func providerID(for identity: MCPClientIdentity?) -> String? {
        guard let developer = identity?.developer else { return nil }
        if developer.hasPrefix("Anthropic") {
            return "anthropic"
        }
        if developer.hasPrefix("OpenAI") {
            return "openai"
        }
        return nil
    }

    private func prepareTask() {
        guard let active = browser.activeTab, !active.isPrivate else { return }
        if let task {
            self.task = toolkit.followActiveTab() ?? task
        } else {
            let started = AgentTaskContext(
                id: UUID(), tabID: active.id, anchorID: browser.anchorID(of: active.id), driver: .external(name: displayName))
            toolkit.beginTask(started)
            task = started
        }
        guard let task, trace?.anchorID != task.anchorID else { return }
        finishTrace()
        let id = toolkit.log.beginTask("", tabID: task.anchorID, providerID: Self.providerID(for: identity))
        let traced = AgentTaskContext(id: id, tabID: task.tabID, anchorID: task.anchorID, isContinuation: true, driver: task.driver)
        toolkit.continueTask(traced)
        self.task = traced
        trace = (id, task.anchorID)
        browser.setAgentWorking(true, inAnchor: task.anchorID)
    }

    private func finishTrace() {
        idleFinish?.cancel()
        idleFinish = nil
        guard let trace else { return }
        self.trace = nil
        toolkit.log.completeTask(trace.id, response: String(localized: "\(displayName) finished working."))
        browser.setAgentWorking(false, inAnchor: trace.anchorID)
    }

    private func scheduleIdleFinish() {
        guard trace != nil else { return }
        idleFinish = Task { [weak self, idle] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled, let self, !busy else { return }
            finishTrace()
        }
    }

    private static func content(from arguments: [String: Value]) -> GeneratedContent? {
        guard let data = try? JSONEncoder().encode(Value.object(arguments)) else { return nil }
        return try? GeneratedContent(json: String(decoding: data, as: UTF8.self))
    }

    private func failure(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}
