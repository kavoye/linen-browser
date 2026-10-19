// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing
import WebKit

@testable import Linen

nonisolated struct EvalAttempt: Codable, Sendable {
    struct Check: Codable, Sendable {
        let name: String
        let passed: Bool
        var forbidden = false
    }

    struct Step: Codable, Sendable {
        let kind: String
        let tool: String
        let text: String
    }

    let task: String
    let version: Int
    let family: String
    let covers: [String]
    let tags: [String]
    let variant: String
    let attempt: Int
    var skipped: String?
    var passed = false
    var checks: [Check] = []
    var status = "not_run"
    var generations = 0
    var tools: [String] = []
    var failedTools = 0
    var inputTokens = 0
    var cachedTokens = 0
    var outputTokens = 0
    var elapsedMilliseconds = 0
    var consentRequests = 0
    var questions = 0
    var answer = ""
    var trace: [Step] = []
}

@MainActor
struct EvalRunner {
    let configuration: EvalConfiguration
    let provider: Provider

    private static func isolateDefaults() throws -> () -> Void {
        let suiteName = TestDefaults.name("Linen.Evals")
        let originalDefaults = LLMSettings.defaults
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        LLMSettings.defaults = defaults
        return {
            LLMSettings.defaults = originalDefaults
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private static func scratchFolder(_ name: String) throws -> URL {
        let folder = TestFiles.directory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func run(_ task: EvalTask, variant: EvalVariant, attempt: Int) async throws -> EvalAttempt {
        var result = EvalAttempt(task: task.id, version: task.version, family: task.family, covers: task.covers,
                                 tags: task.tags.sorted(), variant: variant.name, attempt: attempt)
        let restoreDefaults = try Self.isolateDefaults()
        defer { restoreDefaults() }
        if task.tags.contains("foreground"), !configuration.foreground {
            result.skipped = "needs the window in front; run with --foreground"
            return result
        }
        let store = EvalStore()
        let site = try await EvalSite.start(task.routes.merging(task.stateful?(store) ?? [:]) { _, stateful in stateful })
        let window = EvalWindow(title: "Linen eval", placement: configuration.foreground ? .front : .behind)
        defer { window.close() }
        let database = AppDatabase.temporary()
        let downloads = try Self.scratchFolder("eval-downloads")
        defer { try? FileManager.default.removeItem(at: downloads) }
        let browser = BrowserModel(database: database, downloads: DownloadManager(destinationFolder: downloads, asksWhereToSave: false, persists: false))
        let log = ConversationLog(database: database)
        let questions = AgentQuestionModel()
        let hits = task.search.map { SearchHit(title: $0.title, url: site.url($0.path).absoluteString, snippet: $0.snippet) }
        let chosen = try task.upload.map { upload in
            let file = TestFiles.directory.appendingPathComponent(upload.name)
            try upload.contents.write(to: file, atomically: true, encoding: .utf8)
            return [file]
        }
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log, questions: questions, services: .init(
            search: { _ in hits },
            resolveVideo: { _ in ResolvedVideo(videoID: nil, fallbackURL: site.url("/")) },
            chooseFiles: { _ in chosen }
        ))
        let registry = ModelProviderRegistry(credentials: EvalCredentials(environmentKey: provider.environmentKey ?? "LINEN_EVAL_KEY"))
        let resolved = registry.resolve(provider)
        guard resolved.availability == .available else {
            throw EvalError.unavailable(String(describing: resolved.availability))
        }
        let effort = LLMSettings.ReasoningEffort(rawValue: configuration.effort) ?? .low
        let agent = try #require(resolved.makeAgent(
            model: configuration.model ?? provider.defaultModel, reasoningEffort: effort, toolkit: toolkit, log: log
        ) as? AnyLanguageModelAgent)

        let offered = try Self.offeredTools(agent)
        if let missing = task.requires.subtracting(offered).sorted().first {
            result.skipped = "\(missing) is not offered by this provider"
            return result
        }

        var events: [AgentEvaluationEvent] = []
        var traceTab: UUID?
        var trace = EvalTrace()
        agent.onEvaluationEvent = { event in
            events.append(event)
            if let traceTab {
                trace.collect(log.checkpoint(forTab: traceTab)?.transcript)
            }
            window.update(browser)
        }
        let turn = AgentTurnModel(browser: browser, log: log, speech: EvalSpeech())
        turn.use(agent)
        let tab = browser.newTab(url: site.url(task.start))
        traceTab = tab.id
        window.update(browser)
        _ = await PageSettle.untilIdle(tab.webView, timeout: .seconds(30))
        let context = EvalContext(site: site, browser: browser, toolkit: toolkit, tab: tab)
        context.store = store
        Self.grantControl(in: browser)
        try await task.setup?(context)
        Self.grantControl(in: browser)
        _ = await waitUntil(timeout: .seconds(5), tick: .milliseconds(50)) {
            browser.tabs.allSatisfy { $0.webView.url == nil || $0.title != BrowserTab.placeholderTitle }
        }
        window.update(browser)
        defer {
            turn.cancel()
            questions.abandon()
            agent.discardAllSessions()
            for open in browser.tabs {
                open.webView.stopLoading()
            }
        }

        var answers = task.answers
        var consentRequests = 0
        let decision = task.consent
        let access = task.siteAccess
        let mentioned = context.mentioned
        let started = ContinuousClock.now
        let finished = await TabAssistantAccessCenter.$decisionForTesting.withValue(.init { _, _ in access }) {
            await AgentActionConsent.$scopedPolicy.withValue(AgentActionPolicy(storage: EvalGrantStorage())) {
                await AgentActionConsent.$decisionForTesting.withValue(.init { _, _, _ in
                    consentRequests += 1
                    return decision
                }) {
                    _ = turn.run(utterance: task.instruction(on: site), mentionedTabIDs: mentioned)
                    return await waitUntil(timeout: task.timeout, tick: .milliseconds(200)) {
                        if questions.ask != nil {
                            result.questions += 1
                            if answers.isEmpty {
                                questions.abandon()
                            } else {
                                questions.answer(answers.removeFirst())
                            }
                        }
                        return !turn.isRunning
                    }
                }
            }
        }
        if !finished {
            turn.cancel()
        }
        result.consentRequests = consentRequests
        result.answer = turn.reply.text ?? ""
        Self.record(events, finished: finished, since: started, into: &result)
        trace.collect(log.checkpoint(forTab: tab.id)?.transcript)
        result.trace = trace.steps
        await Self.grade(task, context: context, result: &result)
        withExtendedLifetime(site) {}
        return result
    }

    private static func record(_ events: [AgentEvaluationEvent], finished: Bool, since started: ContinuousClock.Instant, into result: inout EvalAttempt) {
        let elapsed = started.duration(to: .now).components
        result.elapsedMilliseconds = max(0, Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000))
        result.status = finished ? (events.last { $0.kind == "terminal" }?.values["status"] ?? "unknown") : "timeout"
        result.generations = events.count { $0.kind == "generation" }
        result.tools = events.filter { $0.kind == "tool_proposed" }.compactMap { $0.values["name"] }
        result.failedTools = events.count { $0.kind == "tool_failed" }
        func total(_ key: String) -> Int {
            events.filter { $0.kind == "provider_usage" }.reduce(0) { $0 + (Int($1.values[key] ?? "") ?? 0) }
        }
        result.inputTokens = total("input_tokens")
        result.cachedTokens = total("cached_tokens")
        result.outputTokens = total("output_tokens")
    }

    private static func grade(_ task: EvalTask, context: EvalContext, result: inout EvalAttempt) async {
        context.answer = result.answer
        context.tools = result.tools
        for check in task.checks {
            result.checks.append(.init(name: check.name, passed: await check.check(context), forbidden: check.forbidden))
        }
        result.passed = !result.checks.isEmpty && result.checks.allSatisfy(\.passed)
    }

    private static func grantControl(in browser: BrowserModel) {
        for open in browser.tabs {
            open.assistantAccess.persistsAnswers = false
            open.assistantAccess.pageChanged(url: open.webView.url)
            open.assistantAccess.set(.control)
        }
    }

    static func offeredTools(_ agent: AnyLanguageModelAgent) throws -> Set<String> {
        let first = agent.tools(for: Transcript(entries: []))
        let loadable = first.compactMap { $0 as? LoadToolsTool }.first?.toolNames ?? []
        return Set(first.map(\.name)).union(loadable)
    }
}

struct EvalTrace {
    private(set) var steps: [EvalAttempt.Step] = []
    private var positions: [String: Int] = [:]

    mutating func collect(_ transcript: Transcript?) {
        guard let transcript else { return }
        for entry in transcript {
            switch entry {
            case .prompt(let prompt):
                let text = String(AnyLanguageModelAgent.text(in: prompt.segments).prefix(400))
                if positions[entry.id] != nil || steps.last?.kind != "prompt" || steps.last?.text != text {
                    add(entry.id, .init(kind: "prompt", tool: "", text: text))
                }
            case .toolCalls(let calls):
                for call in calls {
                    add("call" + call.id, .init(kind: "call", tool: call.toolName, text: call.arguments.jsonString))
                }
            case .toolOutput(let output):
                add("output" + output.id, .init(kind: "output", tool: output.toolName,
                                                 text: String(AnyLanguageModelAgent.text(in: output.segments).prefix(1_200))))
            case .response(let response):
                add(entry.id, .init(kind: "response", tool: "", text: String(AnyLanguageModelAgent.text(in: response.segments).prefix(1_200))))
            default:
                break
            }
        }
    }

    private mutating func add(_ key: String, _ step: EvalAttempt.Step) {
        if let position = positions[key] {
            steps[position] = step
        } else {
            positions[key] = steps.count
            steps.append(step)
        }
    }
}
