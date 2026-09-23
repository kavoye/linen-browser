// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIRequest: Sendable {
    var path: [String]
    var method = "POST"
    var query: [String: String] = [:]
    var body: Data?
    var contentType = "application/json"
}

nonisolated struct OpenAIHTTPResult: Sendable {
    let data: Data
    let status: Int
    let headers: [String: String]
    func json() throws -> OpenAIJSON {
        try .decode(data)
    }
}

nonisolated struct OpenAIEvent: Equatable, Sendable {
    let type: String
    let payload: OpenAIJSON
    let id: String?
}

nonisolated protocol OpenAITransport: Sendable {
    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult
    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error>
}

nonisolated struct OpenAIFailure: LocalizedError, Sendable {
    enum Kind: String, Sendable {
        case configuration, http, invalidResponse, incomplete, streamInterrupted, contextLimit, unsupportedAction
    }
    let kind: Kind
    var status: Int?
    var code: String?
    var usage: OpenAIUsage?
    var retryAfter: Double?

    static func event(_ payload: OpenAIJSON) -> Self {
        let code = payload["error"]["code"].string ?? payload["code"].string
        return .init(kind: code == "context_length_exceeded" ? .contextLimit : .http,
                     status: payload["status"].int, code: code)
    }

    var errorDescription: String? {
        switch kind {
        case .configuration:
            "The OpenAI configuration is invalid. Review the provider settings."
        case .http:
            "OpenAI could not complete the request. Check the provider settings and try again."
        case .invalidResponse:
            "OpenAI returned a response Linen could not process."
        case .incomplete:
            "OpenAI stopped before completing the response. Your confirmed progress is saved."
        case .streamInterrupted:
            "The OpenAI connection ended before the response completed."
        case .contextLimit:
            "The OpenAI conversation needs compaction before continuing."
        case .unsupportedAction:
            "OpenAI requested an action that this version of Linen cannot execute."
        }
    }
}

nonisolated final class OpenAIHTTPTransport: OpenAITransport {
    let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let headers: [String: String]

    init(baseURL: URL, apiKey: String, session: URLSession = .shared, headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.headers = headers
    }

    func urlRequest(_ request: OpenAIRequest) throws -> URLRequest {
        guard ["https", "http"].contains(baseURL.scheme), baseURL.host != nil,
            baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
            !request.path.isEmpty,
            request.path.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\")
                    && !$0.contains("%") && !$0.contains(where: { $0.isNewline || $0.asciiValue == 0 })
            })
        else {
            throw OpenAIFailure(kind: .configuration)
        }
        var url = baseURL
        for component in request.path {
            url.appendPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw OpenAIFailure(kind: .configuration) }
        if !request.query.isEmpty {
            components.queryItems = request.query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components.url else { throw OpenAIFailure(kind: .configuration) }
        var result = URLRequest(url: finalURL, timeoutInterval: 300)
        result.httpMethod = request.method
        result.httpBody = request.body
        for (key, value) in headers {
            result.setValue(value, forHTTPHeaderField: key)
        }
        result.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        result.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
        return result
    }

    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        let (data, response) = try await session.data(for: urlRequest(request), delegate: OpenAIRedirectPolicy())
        return try Self.checked(data: data, response: response)
    }

    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var prepared = try urlRequest(request)
                    prepared.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: prepared, delegate: OpenAIRedirectPolicy())
                    guard let http = response as? HTTPURLResponse else { throw OpenAIFailure(kind: .invalidResponse) }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            if errorData.count >= 64 * 1_024 {
                                break
                            }
                            errorData.append(byte)
                        }
                        _ = try Self.checked(data: errorData, response: response)
                        throw OpenAIFailure(kind: .http, status: http.statusCode)
                    }
                    if http.mimeType == "application/json" {
                        var data = Data()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            data.append(byte)
                        }
                        let payload = try OpenAIJSON.decode(data)
                        let status = payload["status"].string ?? "completed"
                        continuation.yield(.init(type: "response." + status, payload: ["response": payload], id: nil))
                    } else {
                        var framer = OpenAISSEFramer()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            if let event = try framer.consume(byte) {
                                continuation.yield(event)
                            }
                        }
                        if let event = try framer.finish() {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func checked(data: Data, response: URLResponse) throws -> OpenAIHTTPResult {
        guard let http = response as? HTTPURLResponse else { throw OpenAIFailure(kind: .invalidResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? OpenAIJSON.decode(data)
            let code = error?["error"]["code"].string
            throw OpenAIFailure(kind: code == "context_length_exceeded" ? .contextLimit : .http,
                                status: http.statusCode, code: code,
                                retryAfter: AgentProviderRetry.retryAfter(http.value(forHTTPHeaderField: "Retry-After"),
                                    milliseconds: http.value(forHTTPHeaderField: "retry-after-ms")))
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String {
                result[key.lowercased()] = value
            }
        }
        return .init(data: data, status: http.statusCode, headers: headers)
    }
}

nonisolated final class OpenAIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated struct OpenAISSEParser {
    private var type = ""
    private var id: String?
    private var lines: [String] = []
    private var bytes = 0

    mutating func consume(_ line: String) throws -> OpenAIEvent? {
        if line.isEmpty {
            defer {
                type = ""
                lines = []
                bytes = 0
            }
            guard !lines.isEmpty else { return nil }
            let text = lines.joined(separator: "\n")
            guard text != "[DONE]" else { return nil }
            let payload = try OpenAIJSON.decode(Data(text.utf8))
            return .init(type: payload["type"].string ?? type, payload: payload, id: id)
        }
        guard !line.hasPrefix(":") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let value = parts.count > 1 ? String(parts[1].dropFirst(parts[1].hasPrefix(" ") ? 1 : 0)) : ""
        switch parts[0] {
        case "event":
            type = value
        case "id":
            if !value.contains("\0") {
                id = value
            }
        case "data":
            bytes += value.utf8.count
            guard bytes <= 64 * 1_024 * 1_024 else { throw OpenAIFailure(kind: .invalidResponse) }
            lines.append(value)
        default:
            break
        }
        return nil
    }
}

nonisolated struct OpenAISSEFramer {
    private var parser = OpenAISSEParser()
    private var line = Data()
    private var skipLF = false
    private var firstLine = true

    mutating func consume(_ byte: UInt8) throws -> OpenAIEvent? {
        if byte == 10, skipLF {
            skipLF = false
            return nil
        }
        skipLF = byte == 13
        if byte == 10 || byte == 13 {
            return try endLine()
        }
        guard line.count < 64 * 1_024 * 1_024 else { throw OpenAIFailure(kind: .invalidResponse) }
        line.append(byte)
        return nil
    }

    mutating func finish() throws -> OpenAIEvent? {
        if !line.isEmpty {
            _ = try endLine()
        }
        return try parser.consume("")
    }

    private mutating func endLine() throws -> OpenAIEvent? {
        var text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if firstLine, text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        firstLine = false
        return try parser.consume(text)
    }
}
