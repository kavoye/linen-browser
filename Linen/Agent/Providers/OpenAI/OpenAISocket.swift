// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated protocol OpenAISocketConnection: Sendable {
    func send(_ event: OpenAIJSON) async throws
    func receive() async throws -> OpenAIJSON
    func close() async
}

actor OpenAISocket: OpenAISocketConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) throws {
        guard let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            ["https", "http"].contains(parts.scheme)
        else { throw OpenAIFailure(kind: .configuration) }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        var request = request
        request.url = parts.url
        request.httpBody = nil
        request.httpMethod = "GET"
        session = URLSession(configuration: .ephemeral, delegate: OpenAIRedirectPolicy(), delegateQueue: nil)
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1_024 * 1_024
        task.resume()
    }

    deinit {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func send(_ event: OpenAIJSON) async throws {
        try await task.send(.string(event.text()))
    }
    func receive() async throws -> OpenAIJSON {
        switch try await task.receive() {
        case .string(let value):
            try .decode(Data(value.utf8))
        case .data(let value):
            try .decode(value)
        @unknown default:
            throw OpenAIFailure(kind: .invalidResponse)
        }
    }
    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

nonisolated final class OpenAIWebSocketTransport: OpenAITransport {
    private let http: OpenAIHTTPTransport
    private let pool: OpenAIResponseSocketPool

    init(http: OpenAIHTTPTransport) {
        self.http = http
        pool = OpenAIResponseSocketPool {
            try OpenAISocket(request: http.urlRequest(.init(path: ["responses"], method: "GET")))
        }
    }

    func send(_ request: OpenAIRequest) async throws -> OpenAIHTTPResult {
        try await http.send(request)
    }

    func discardHistory(cancelActive: Bool) {
        Task { await pool.discardHistory(cancelActive: cancelActive) }
    }
    func events(_ request: OpenAIRequest) -> AsyncThrowingStream<OpenAIEvent, any Error> {
        guard request.path == ["responses"] else { return http.events(request) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let data = request.body else { throw OpenAIFailure(kind: .configuration) }
                    try await pool.generate(try .decode(data)) { continuation.yield($0) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor OpenAIResponseSocketPool {
    struct Channel {
        let id = UUID()
        let socket: any OpenAISocketConnection
        let created = ContinuousClock.now
        var busy = false
        var prefix: [OpenAIJSON] = []
        var responseID: String?
    }
    private var channels: [Channel] = []
    private let connect: @Sendable () throws -> any OpenAISocketConnection
    init(connect: @escaping @Sendable () throws -> any OpenAISocketConnection) {
        self.connect = connect
    }

    func discardHistory(cancelActive: Bool) async {
        let closing = channels.filter { cancelActive || !$0.busy }
        channels.removeAll { candidate in closing.contains { $0.id == candidate.id } }
        for channel in closing {
            await channel.socket.close()
        }
    }

    func generate(_ original: OpenAIJSON, onEvent: @Sendable (OpenAIEvent) -> Void) async throws {
        try Task.checkCancellation()
        let expired = channels.filter { !$0.busy && ContinuousClock.now - $0.created > .seconds(3_300) }
        channels.removeAll { candidate in expired.contains { $0.id == candidate.id } }
        for channel in expired {
            await channel.socket.close()
        }
        let input = original["input"].array ?? []
        let matching = channels.firstIndex { !$0.busy && !$0.prefix.isEmpty && input.starts(with: $0.prefix) }
        let index: Int
        if let available = matching ?? channels.firstIndex(where: { !$0.busy }) {
            index = available
        } else {
            channels.append(Channel(socket: try connect()))
            index = channels.count - 1
        }
        var channel = channels[index]
        channels[index].busy = true
        var body = original.object ?? [:]
        body.removeValue(forKey: "stream")
        body.removeValue(forKey: "background")
        body["type"] = "response.create"
        if matching != nil, let id = channel.responseID {
            body["previous_response_id"] = .string(id)
            body["input"] = .array(Array(input.dropFirst(channel.prefix.count)))
        }
        let socket = channel.socket
        do {
            let terminal = try await withTaskCancellationHandler {
                try await socket.send(.object(body))
                while true {
                    try Task.checkCancellation()
                    let payload = try await socket.receive()
                    guard let type = payload["type"].string else { throw OpenAIFailure(kind: .invalidResponse) }
                    if type == "error" {
                        throw OpenAIFailure(kind: payload["error"]["code"] == "context_length_exceeded" ? .contextLimit : .http)
                    }
                    if ["response.completed", "response.failed", "response.incomplete", "response.cancelled"].contains(type) {
                        return payload
                    }
                    onEvent(.init(type: type, payload: payload, id: payload["event_id"].string))
                }
            } onCancel: {
                Task { await socket.close() }
            }
            channel.busy = false
            let response = terminal["response"]
            if response["status"] == "completed", let output = response["output"].array, let id = response["id"].string {
                channel.prefix = input + output
                channel.responseID = id
            } else {
                channel.prefix = []
                channel.responseID = nil
            }
            if let current = channels.firstIndex(where: {
                $0.id == channel.id }) { channels[current] = channel
            }
            onEvent(.init(type: terminal["type"].string ?? "", payload: terminal, id: terminal["event_id"].string))
        } catch {
            channels.removeAll { $0.id == channel.id }
            await socket.close()
            throw error
        }
    }
}
