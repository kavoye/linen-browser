// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import CryptoKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct BrowserAgentBenchWorker {
    @Test(.boundedWebViews, .enabled(if: ProcessInfo.processInfo.environment["BAB_CONTROL_URL"] != nil))
    func benchmarkWorker() async throws {
        let client = try BenchClient()
        do {
            let start: BenchStart = try await client.get("start")
            try #require(start.protocolVersion == 1)
            try await execute(start, client: client)
        } catch {
            try? await client.post("finish", ["status": "agent_error", "error": "Benchmark worker failed; inspect the local test log."])
            throw error
        }
    }

    private func execute(_ start: BenchStart, client: BenchClient) async throws {
        let preferences = "Linen.Benchmark.\(UUID().uuidString)"
        let originalDefaults = LLMSettings.defaults
        let defaults = try #require(UserDefaults(suiteName: preferences))
        LLMSettings.defaults = defaults
        defer {
            LLMSettings.defaults = originalDefaults
            defaults.removePersistentDomain(forName: preferences)
        }
        try await run(start, client: client)
    }

    private func run(_ start: BenchStart, client: BenchClient) async throws {
        let settings = start.config.settings ?? BenchSettings()
        let window = BenchWindow(headless: settings.headless)
        defer { window.close() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WKWebsiteDataStore.nonPersistent()
        let permissions = SitePermissions(storageURL: folder.appendingPathComponent("permissions.json"))
        let database = AppDatabase.temporary()
        let browser = BrowserModel(database: database, sitePermissions: permissions, webViewFactory: {
            let configuration = WebViewPool.makeConfiguration()
            configuration.websiteDataStore = store
            return WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: configuration)
        })
        let log = ConversationLog(database: database)
        let questions = AgentQuestionModel()
        let toolkit = AgentToolkit(browser: browser, media: MediaCenter(), log: log, questions: questions,
                                   services: .init(search: { query in
                                    settings.searchMode == .live ? await SnippetFetcher.search(query: query) : []
                                   }, resolveVideo: { _ in
                                    ResolvedVideo(videoID: nil, fallbackURL: start.url)
                                   }))
        let provider = try start.config.providerConfiguration()
        let resolved = ModelProviderRegistry(credentials: BenchCredentials(environmentKey: "BAB_PROVIDER_KEY")).resolve(provider)
        try #require(resolved.availability == .available, "Requested provider is unavailable")
        let effort = LLMSettings.ReasoningEffort(rawValue: settings.reasoningEffort)
        let runner = try OpenAISettingsStore.$scoped.withValue(settings.openAIOptions(model: start.config.model, adapter: provider.adapter)) {
            resolved.makeAgent(model: start.config.model, reasoningEffort: try #require(effort), toolkit: toolkit, log: log)
        }
        let agent = try #require(runner as? AnyLanguageModelAgent)
        var telemetry = BenchTelemetry()
        agent.onEvaluationEvent = {
            telemetry.events.append($0)
            window.update(browser)
        }
        let turn = AgentTurnModel(browser: browser, log: log, speech: BenchSpeech())
        turn.use(agent)
        let tab = browser.newTab(url: start.url)
        window.update(browser)
        try #require(await PageSettle.untilIdle(tab.webView, timeout: .seconds(30)))
        tab.assistantAccess.persistsAnswers = false
        tab.assistantAccess.pageChanged(url: start.url)
        tab.assistantAccess.set(.control)
        defer { stop(turn, questions: questions, agent: agent, browser: browser) }
        let prompt = AgentInstructions.text(for: agent.budget.instructionTier)
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        let webKit = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let capabilities = settings.headless ? ["web"] : ["web", "native-keyboard", "screenshots"]
        try #require(Set(start.requiredCapabilities ?? ["web"]).isSubset(of: Set(capabilities)))
        try await client.post("ready", BenchReady(capabilities: capabilities, metadata: [
            "model": start.config.model,
            "browser_version": "WebKit \(webKit)",
            "agent_version": ProcessInfo.processInfo.environment["BAB_LINEN_REVISION"] ?? "unknown",
            "source_sha256": ProcessInfo.processInfo.environment["BAB_LINEN_SOURCE_SHA256"] ?? "unknown",
            "adapter_version": "5",
            "openai_transport": provider.adapter == .openAIResponses ? "native_http_sse" : "unused",
            "system_prompt_sha256": digest,
            "observations": "Linen page tools and screenshots",
        ], settings: [
            "headless": String(settings.headless),
            "search_mode": settings.searchMode.rawValue,
            "consent_policy": "deny_consequential",
            "question_policy": "abandon_unexpected",
            "reasoning_effort": settings.reasoningEffort,
            "max_model_requests": settings.maxModelRequests.map(String.init) ?? "unlimited",
            "tool_search": String(settings.toolSearch),
            "hover_policy": "requires_user_foreground_window",
            "preferences": "isolated_defaults",
            "openai_options": "explicit_tool_search_otherwise_defaults_no_storage",
        ]))
        let grants = BenchGrantStorage()
        let policy = AgentActionPolicy(storage: grants)
        var publishedEvents = 0
        var cancelled = false
        let started = ContinuousClock.now
        try await AgentExecutionPolicy.$scoped.withValue(.init(maxModelRequests: settings.maxModelRequests)) {
            try await AgentActionConsent.$scopedPolicy.withValue(policy) {
                try await AgentActionConsent.$decisionForTesting.withValue(.init { _, _, _ in
                    telemetry.consentRequests += 1
                    return .decline
                }) {
                    _ = turn.run(utterance: start.instruction)
                    _ = try await waitUntil(timeout: .seconds(start.deadlineSeconds), tick: .milliseconds(200)) {
                        guard turn.isRunning, !Task.isCancelled else { return true }
                        let cancellation: BenchCancellation = try await client.get("status")
                        if cancellation.cancelled {
                            cancelled = true
                            turn.cancel()
                            return true
                        }
                        while publishedEvents < telemetry.events.count {
                            try await client.post("event", telemetry.events[publishedEvents])
                            publishedEvents += 1
                        }
                        if questions.ask != nil {
                            telemetry.userQuestions += 1
                            questions.abandon()
                        }
                        return !turn.isRunning
                    }
                }
            }
        }
        let timedOut = turn.isRunning
        if timedOut {
            turn.cancel()
        }
        for event in telemetry.events.dropFirst(publishedEvents) {
            try await client.post("event", event)
        }
        var usage = telemetry.usage
        let elapsed = started.duration(to: .now).components
        usage["native_elapsed_ms"] = max(0, Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))
        try await client.post("finish", BenchFinish(
                                status: telemetry.status(timedOut: timedOut, cancelled: cancelled), answer: turn.reply.text ?? "", usage: usage))
    }

    private func stop(_ turn: AgentTurnModel, questions: AgentQuestionModel, agent: AnyLanguageModelAgent, browser: BrowserModel) {
        turn.cancel()
        questions.abandon()
        agent.discardAllSessions()
        for tab in browser.tabs {
            tab.webView.stopLoading()
        }
    }
}

private struct BenchCancellation: Decodable {
    let cancelled: Bool
}

private struct BenchStart: Decodable {
    let protocolVersion: Int
    let instruction: String
    let url: URL
    let deadlineSeconds: Int
    let config: BenchConfiguration
    let requiredCapabilities: [String]?
}

private struct BenchConfiguration: Decodable {
    let model: String
    let provider: String
    let baseUrl: URL?
    let credentialEnv: String
    let revision: String
    let settings: BenchSettings?

    func providerConfiguration() throws -> Provider {
        let adapter: Provider.Adapter
        let fallback: URL
        switch provider {
        case "openai":
            adapter = .openAIResponses
            fallback = URL(string: "https://api.openai.com/v1")!
        case "anthropic":
            adapter = .anthropic
            fallback = URL(string: "https://api.anthropic.com/v1")!
        case "google":
            adapter = .gemini
            fallback = URL(string: "https://generativelanguage.googleapis.com")!
        case "compatible":
            adapter = .openAICompatible
            fallback = try #require(baseUrl, "Compatible provider needs base_url")
        default:
            throw BenchError.invalidConfiguration
        }
        return Provider(id: "benchmark", name: "Benchmark", blurb: "", symbol: "", baseURL: baseUrl ?? fallback,
                        wire: adapter == .openAIResponses ? .responses : .chatCompletions, adapter: adapter,
                        auth: .bearer, environmentKey: credentialEnv, defaultModel: model)
    }
}

private struct BenchReady: Encodable {
    let capabilities: [String]
    let metadata: [String: String]
    let settings: [String: String]

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in metadata {
            try container.encode(value, forKey: Key(stringValue: key))
        }
        try container.encode(capabilities, forKey: Key(stringValue: "capabilities"))
        try container.encode(settings, forKey: Key(stringValue: "settings"))
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? {
            nil
        }
        init(stringValue: String) {
            self.stringValue = stringValue
        }
        init?(intValue: Int) {
            return nil
        }
    }
}

private struct BenchFinish: Encodable {
    let status: String
    let answer: String
    let usage: [String: Int]
}

private enum BenchError: Error {
    case invalidConfiguration
    case http(Int)
}

private struct BenchClient {
    let base: URL
    let token: String

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        base = try #require(environment["BAB_CONTROL_URL"].flatMap(URL.init(string:)))
        token = try #require(environment["BAB_CONTROL_TOKEN"])
        try #require(base.host() == "127.0.0.1" && base.scheme == "http")
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path, body: nil)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Encodable>(_ path: String, _ body: T) async throws {
        _ = try await request(path, body: JSONEncoder().encode(body))
    }

    private func request(_ path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BenchError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

private final class BenchSpeech: SpeechOutput {
    var isMuted = true
    var onSpeakingChange: ((Bool) -> Void)?
    func speak(_ text: String) {}
    func stopSpeaking() {}
}

private final class BenchGrantStorage: AgentGrantStorage {
    var grantData: Data?
}

private nonisolated struct BenchCredentials: ProviderCredentialStore {
    let environmentKey: String
    func key(for provider: Provider) -> String? {
        ProcessInfo.processInfo.environment[environmentKey]
    }
    func isConfigured(_ provider: Provider) -> Bool {
        key(for: provider)?.isEmpty == false
    }
    func source(for provider: Provider) -> CredentialStore.Source {
        .environment(environmentKey)
    }
    func masked(for provider: Provider) -> String? {
        nil
    }
    func save(_ key: String, for provider: Provider) -> String? {
        "Read-only benchmark credentials"
    }
    func delete(for provider: Provider) {}
}
