// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

nonisolated final class OpenAILiveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [OpenAIJSON] = []
    private var requestCount = 0
    private var label = "preflight"
    let requestLimit: Int

    init(requestLimit: Int = 20) {
        self.requestLimit = requestLimit
    }

    func select(_ name: String) {
        lock.withLock { label = name }
    }

    func begin() throws -> String {
        try lock.withLock {
            guard requestCount < requestLimit else { throw OpenAILiveFailure.requestLimit }
            requestCount += 1
            return label
        }
    }

    var snapshot: [OpenAIJSON] {
        lock.withLock { records }
    }

    func record(label: String, started: ContinuousClock.Instant, firstText: Int?, response: OpenAIJSON, error: (any Error)? = nil) {
        let elapsed = started.duration(to: .now).components
        let usage = OpenAIUsage(raw: response["usage"])
        var entry: OpenAIJSON = [
            "check": .string(label),
            "elapsed_ms": .integer(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000),
            "first_text_ms": firstText.map { .integer(Int64($0)) } ?? .null,
            "status": response["status"].string.map(OpenAIJSON.string) ?? .string(error == nil ? "received" : "failed"),
            "usage": .object(usage.eventValues.mapValues(OpenAIJSON.string)),
            "output_types": .array((response["output"].array ?? []).compactMap { $0["type"].string.map(OpenAIJSON.string) }),
        ]
        if let error {
            entry["error"] = .string(Self.errorCode(error))
        }
        lock.withLock { records.append(entry) }
    }

    static func errorCode(_ error: any Error) -> String {
        if let failure = error as? OpenAIFailure {
            return failure.kind.rawValue + (failure.status.map { "_\($0)" } ?? "")
        }
        if let failure = error as? OpenAILiveFailure {
            return failure.rawValue
        }
        if let failure = error as? OpenAIHostedLiveFailure {
            return "hosted_" + failure.rawValue
        }
        if let failure = error as? OpenAIFileLibraryFailure {
            return "file_" + failure.rawValue
        }
        if let failure = error as? OpenAIVoiceFailure {
            return "voice_" + String(describing: failure)
        }
        if error is CancellationError {
            return "cancelled"
        }
        if error is DecodingError {
            return "json_decoding_error"
        }
        if let error = error as? URLError {
            return "url_error_\(error.code.rawValue)"
        }
        return "transport_or_validation_error"
    }
}

nonisolated enum OpenAILiveFailure: String, Error {
    case requestLimit, invariant, missingCredential
}

nonisolated struct OpenAILiveTransport: OpenAITransport {
    let base: any OpenAITransport
    let recorder: OpenAILiveRecorder

    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        let label = try recorder.begin()
        let started = ContinuousClock.now
        do {
            let result = try await base.send(request)
            recorder.record(label: label, started: started, firstText: nil, response: (try? result.json()) ?? .null)
            return result
        } catch {
            recorder.record(label: label, started: started, firstText: nil, response: .null, error: error)
            throw error
        }
    }

    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let started = ContinuousClock.now
                var label = "request_limit"
                var firstText: Int?
                var recorded = false
                do {
                    label = try recorder.begin()
                    for try await event in base.events(request) {
                        try Task.checkCancellation()
                        if firstText == nil, event.type == "response.output_text.delta", event.payload["delta"].string?.isEmpty == false {
                            let elapsed = started.duration(to: .now).components
                            firstText = Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
                        }
                        if ["response.completed", "response.incomplete", "response.failed", "response.cancelled"].contains(event.type) {
                            recorder.record(label: label, started: started, firstText: firstText, response: event.payload["response"])
                            recorded = true
                        }
                        continuation.yield(event)
                        if recorded {
                            continuation.finish()
                            return
                        }
                    }
                    throw OpenAIFailure(kind: .streamInterrupted)
                } catch {
                    if !recorded {
                        recorder.record(label: label, started: started, firstText: firstText, response: .null, error: error)
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
