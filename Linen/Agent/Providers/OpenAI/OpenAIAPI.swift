// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIAPI: Sendable {
    let transport: any OpenAITransport

    func request(
        _ path: [String], method: String = "POST", body: OpenAIJSON? = nil,
        query: [String: String] = [:]
    ) async throws -> OpenAIJSON {
        let result = try await transport.send(.init(path: path, method: method, query: query, body: try body?.data()))
        return result.data.isEmpty ? .null : try result.json()
    }

    func createResponse(_ body: OpenAIJSON, onEvent: @Sendable (OpenAIEvent) async -> Void) async throws -> OpenAIJSON {
        var body = body
        body["stream"] = true
        for try await event in transport.events(.init(path: ["responses"], body: try body.data())) {
            try Task.checkCancellation()
            await onEvent(event)
            switch event.type {
            case "response.completed", "response.incomplete", "response.failed", "response.cancelled":
                guard event.payload["response"].object != nil else { throw OpenAIFailure(kind: .invalidResponse) }
                return event.payload["response"]
            case "error":
                throw OpenAIFailure(kind: event.payload["code"].string == "context_length_exceeded" ? .contextLimit : .http)
            default:
                break
            }
        }
        throw OpenAIFailure(kind: .streamInterrupted)
    }

    func retrieveResponse(_ id: String) async throws -> OpenAIJSON {
        try await request(["responses", id], method: "GET")
    }
    func cancelResponse(_ id: String) async throws -> OpenAIJSON {
        try await request(["responses", id, "cancel"])
    }
    func deleteResponse(_ id: String) async throws -> OpenAIJSON {
        try await request(["responses", id], method: "DELETE")
    }
    func responseInputItems(_ id: String, after: String? = nil) async throws -> OpenAIJSON {
        try await request(["responses", id, "input_items"], method: "GET", query: after.map { ["after": $0] } ?? [:])
    }
    func compact(_ body: OpenAIJSON) async throws -> OpenAIJSON {
        try await request(["responses", "compact"], body: body)
    }
    func countInputTokens(_ body: OpenAIJSON) async throws -> OpenAIJSON {
        try await request(["responses", "input_tokens"], body: body)
    }

    func createBackgroundResponse(_ body: OpenAIJSON) async throws -> OpenAIJSON {
        var body = body
        body["background"] = true
        body["stream"] = false
        return try await request(["responses"], body: body)
    }

    func pages(_ path: [String], query: [String: String] = [:]) -> AsyncThrowingStream<OpenAIJSON, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var query = query
                    var cursors: Set<String> = []
                    while true {
                        try Task.checkCancellation()
                        let page = try await request(path, method: "GET", query: query)
                        continuation.yield(page)
                        guard page["has_more"].bool == true else { break }
                        guard let cursor = page["last_id"].string ?? page["data"].array?.last?["id"].string,
                            cursors.insert(cursor).inserted
                        else { throw OpenAIFailure(kind: .invalidResponse) }
                        query["after"] = cursor
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func waitForResponse(_ id: String, interval: Duration = .seconds(1)) async throws -> OpenAIJSON {
        while true {
            try Task.checkCancellation()
            let response = try await retrieveResponse(id)
            guard ["queued", "in_progress"].contains(response["status"].string ?? "") else { return response }
            try await Task.sleep(for: interval)
        }
    }

    func upload(_ path: [String], fields: [String: String], files: [OpenAIUpload]) async throws -> OpenAIJSON {
        try await uploadBytes(path, fields: fields, files: files).json()
    }

    func uploadBytes(_ path: [String], fields: [String: String], files: [OpenAIUpload]) async throws -> OpenAIHTTPResult {
        let boundary = "linen-" + UUID().uuidString
        var data = Data()
        func append(_ text: String) {
            data.append(Data(text.utf8))
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            guard OpenAIUpload.valid(name) else { throw OpenAIFailure(kind: .configuration) }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        for file in files {
            guard OpenAIUpload.valid(file.field), OpenAIUpload.valid(file.filename), OpenAIUpload.valid(file.mimeType) else {
                throw OpenAIFailure(kind: .configuration)
            }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            data.append(file.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return try await transport.send(.init(path: path, body: data, contentType: "multipart/form-data; boundary=\(boundary)"))
    }

    func binary(_ path: [String], method: String = "GET", body: OpenAIJSON? = nil) async throws -> OpenAIHTTPResult {
        try await transport.send(.init(path: path, method: method, body: try body?.data()))
    }

    func download(_ file: OpenAIPresentation.File) async throws -> OpenAIHTTPResult {
        let path = file.containerID.map { ["containers", $0, "files", file.fileID, "content"] }
            ?? ["files", file.fileID, "content"]
        return try await binary(path)
    }
}

nonisolated struct OpenAIUpload: Sendable {
    let field: String
    let filename: String
    let mimeType: String
    let data: Data
    static func valid(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { "\r\n\"\\".contains($0) })
    }
}

nonisolated struct OpenAIUsage: Codable, Equatable, Sendable {
    let raw: OpenAIJSON
    var input: Int? {
        count(raw["input_tokens"])
    }
    var output: Int? {
        count(raw["output_tokens"])
    }
    var cached: Int? {
        count(raw["input_tokens_details"]["cached_tokens"])
    }
    var cacheWrite: Int? {
        count(raw["input_tokens_details"]["cache_write_tokens"])
    }
    var reasoning: Int? {
        count(raw["output_tokens_details"]["reasoning_tokens"])
    }
    var total: Int? {
        count(raw["total_tokens"])
    }
    private func count(_ value: OpenAIJSON) -> Int? {
        value.int.flatMap { $0 >= 0 ? $0 : nil }
    }
    var eventValues: [String: String] {
        [
            "input_tokens": input, "output_tokens": output, "cached_tokens": cached,
            "cache_write_tokens": cacheWrite, "reasoning_tokens": reasoning, "total_tokens": total,
        ]
        .compactMapValues { $0.map(String.init) }
    }
}
