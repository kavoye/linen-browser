// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AnyLanguageModel
import Foundation
import Testing

@testable import Linen

@MainActor
struct OpenAIHostedShellLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"] != nil))
    func hostedShellFileAndContinuation() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_CONFIG"])
        let config = try OpenAIJSON.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        guard config["shell_only"] == true, config["live"] == true else { return }
        let model = config["model"].string ?? LLMSettings.model(for: ProviderCatalog.openAI)
        let destination = URL(fileURLWithPath: try #require(config["report_path"].string))
        let recorder = OpenAILiveRecorder(requestLimit: 8)
        var report: OpenAIJSON = [
            "mode": "live_hosted_shell_acceptance", "status": "running", "model": .string(model),
            "source_sha256": config["source_sha256"], "synthetic_prompt": true, "synthetic_usage": false,
            "competitive_score": false, "max_requests": 8, "max_output_tokens_per_response": 2_048,
            "requests": [], "checks": [], "local_commands_executed": false,
        ]
        func save() throws {
            report["requests"] = .array(recorder.snapshot)
            try report.data().write(to: destination, options: .atomic)
        }
        guard let key = ProcessInfo.processInfo.environment["LINEN_OPENAI_LIVE_KEY"] ?? CredentialStore.key(for: ProviderCatalog.openAI), !key.isEmpty else {
            report["status"] = "blocked_missing_credential"
            try save()
            return
        }
        try save()
        let endpoint = URL(string: "https://api.openai.com/v1")!
        let transport = ShellContainerRecorder(base: OpenAILiveTransport(base: OpenAIHTTPTransport(baseURL: endpoint, apiKey: key), recorder: recorder))
        let api = OpenAIAPI(transport: transport)
        do {
            var settings = OpenAIResponseSettings()
            settings.hostedTools = [OpenAIHostedShell.definition]
            settings.additionalParameters = ["tool_choice": "required", "max_tool_calls": 1]
            let client = OpenAIResponsesClient(endpoint: endpoint, apiKey: key, model: model, settings: settings, transport: transport)
            recorder.select("shell_create_file")
            let first = try await client.respond(transcript: Transcript(),
                prompt: "Use one shell call to write /mnt/data/linen-shell-result.csv containing exactly: "
                    + "a,b,product followed by a newline and 17,19,323 followed by a newline. Provide a download link to this file.",
                images: [], state: client.restoring(nil), tools: [], maxTokens: 2_048, onText: { _ in })
            guard let id = transport.containerIDs.first, transport.containerIDs.count == 1, first.calls.isEmpty,
                  first.state.items.contains(where: { $0["type"] == "shell_call_output" && $0["status"] == "completed" }),
                  let file = first.state.presentation?.files.first(where: { $0.containerID == id && URL(fileURLWithPath: $0.name).lastPathComponent == "linen-shell-result.csv" })
            else { throw OpenAIHostedLiveFailure.fileCitation }
            recorder.select("shell_download_file")
            let bytes = try await api.download(file)
            guard String(data: bytes.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "a,b,product\n17,19,323" else {
                throw OpenAIHostedLiveFailure.fileContents
            }
            report["checks"] = [["name": "shell_file_download", "passed": true, "bytes": .integer(Int64(bytes.data.count))]]
            try save()
            recorder.select("shell_native_continuation")
            let second = try await client.respond(transcript: first.transcript,
                prompt: "Use one shell call to read /mnt/data/linen-shell-result.csv from the same container. Reply with its numeric product.",
                images: [], state: first.state, tools: [], maxTokens: 2_048, onText: { _ in })
            guard second.calls.isEmpty, second.text.contains("323"), second.state.usage?.input != nil,
                  second.state.items.filter({ $0["type"] == "shell_call_output" }).count == 2,
                  second.state.items.filter({ $0["type"] == "shell_call" }).allSatisfy({ $0["environment"]["container_id"].string == id })
            else { throw OpenAILiveFailure.invariant }
            report["checks"] = .array((report["checks"].array ?? []) + [["name": "shell_container_continuation", "passed": true]])
            guard transport.containerIDs == [id] else { throw OpenAILiveFailure.invariant }
            report["automatic_container_reused"] = true
            report["status"] = "passed"
        } catch {
            report["status"] = "failed"
            report["error"] = .string(OpenAILiveRecorder.errorCode(error))
        }
        var cleaned = 0
        for containerID in transport.containerIDs {
            recorder.select("delete_container")
            do {
                _ = try await api.request(["containers", containerID], method: "DELETE")
                cleaned += 1
            } catch {
                report["status"] = "failed"
                report["cleanup_error"] = .string(OpenAILiveRecorder.errorCode(error))
            }
        }
        report["containers_observed"] = .integer(Int64(transport.containerIDs.count))
        report["containers_deleted"] = .integer(Int64(cleaned))
        try save()
        if report["status"] != "passed" { Issue.record("Hosted shell acceptance failed; see the sanitized report.") }
    }
}

nonisolated private final class ShellContainerRecorder: OpenAITransport, @unchecked Sendable {
    let base: any OpenAITransport
    private let lock = NSLock()
    private var identifiers: Set<String> = []
    var containerIDs: Set<String> {
        lock.withLock { identifiers }
    }
    init(base: any OpenAITransport) {
        self.base = base
    }
    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        try await base.send(request)
    }
    private func observe(_ event: OpenAIEvent) {
        let items = (event.payload["response"]["output"].array ?? []) + [event.payload["item"]]
        for item in items where item["type"] == "shell_call" {
            if let id = item["environment"]["container_id"].string, !id.isEmpty {
                _ = lock.withLock { identifiers.insert(id) }
            }
        }
    }
    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in base.events(request) {
                        observe(event)
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
