// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network

nonisolated struct EvalRequest: Sendable, Equatable {
    let method: String
    let path: String
    let query: [String: String]
    let body: String

    var form: [String: String] {
        EvalRequest.decode(body)
    }

    static func decode(_ encoded: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in encoded.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if let key = parts.first {
                fields[key] = parts.count > 1 ? parts[1] : ""
            }
        }
        return fields
    }
}

nonisolated struct EvalResponse: Sendable {
    let status: String
    let headers: [String: String]
    let body: Data

    static func html(_ body: String) -> Self {
        .init(status: "200 OK", headers: ["Content-Type": "text/html; charset=utf-8"], body: Data(body.utf8))
    }

    static func page(_ title: String, _ body: String) -> Self {
        .html("<!doctype html><html><head><meta charset=\"utf-8\"><title>\(title)</title></head><body>\(body)</body></html>")
    }

    static func json(_ body: String) -> Self {
        .init(status: "200 OK", headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    static func download(_ body: String, filename: String) -> Self {
        .init(status: "200 OK", headers: [
            "Content-Disposition": "attachment; filename=\"\(filename)\"",
            "Content-Type": "application/octet-stream",
        ], body: Data(body.utf8))
    }

    static func redirect(_ path: String) -> Self {
        Self(status: "303 See Other", headers: ["Location": path, "Content-Length": "0"], body: Data())
    }

    static let notFound = Self(status: "404 Not Found", headers: ["Content-Type": "text/html; charset=utf-8"],
                               body: Data("<h1>Not found</h1>".utf8))

    fileprivate var encoded: Data {
        var fields = headers
        fields["Content-Length"] = String(body.count)
        fields["Connection"] = "close"
        fields["Cache-Control"] = "no-store"
        let head = (["HTTP/1.1 \(status)"] + fields.map { "\($0): \($1)" }).joined(separator: "\r\n") + "\r\n\r\n"
        return Data(head.utf8) + body
    }
}

nonisolated final class EvalSite: @unchecked Sendable {
    typealias Handler = @Sendable (EvalRequest) -> EvalResponse

    private let listener: NWListener
    private let queue = DispatchQueue(label: "Linen.evals.site")
    private let routes: [String: Handler]
    private let lock = NSLock()
    private var recorded: [EvalRequest] = []

    private init(listener: NWListener, routes: [String: Handler]) {
        self.listener = listener
        self.routes = routes
    }

    deinit {
        listener.cancel()
    }

    var requests: [EvalRequest] {
        lock.withLock { recorded }
    }

    static func start(_ routes: [String: Handler]) async throws -> EvalSite {
        let listener = try NWListener(using: .tcp, on: .any)
        let site = EvalSite(listener: listener, routes: routes)
        listener.newConnectionHandler = { [weak site] connection in
            site?.accept(connection)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: site.queue)
        }
        return site
    }

    func url(_ path: String = "/") -> URL {
        URL(string: "http://127.0.0.1:\(listener.port?.rawValue ?? 0)\(path)")!
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(from: connection, accumulated: Data())
    }

    private func receive(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }
            guard let request = Self.parse(buffer) else {
                if complete || error != nil {
                    connection.cancel()
                } else {
                    receive(from: connection, accumulated: buffer)
                }
                return
            }
            if request.path != "/favicon.ico" {
                lock.withLock { recorded.append(request) }
            }
            let response = routes[request.path]?(request) ?? .notFound
            connection.send(content: response.encoded, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func parse(_ data: Data) -> EvalRequest? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<split.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        let length = lines.dropFirst().compactMap { line -> Int? in
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].lowercased() == "content-length" else { return nil }
            return Int(pair[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        let target = String(parts[1])
        let pieces = target.split(separator: "?", maxSplits: 1).map(String.init)
        return EvalRequest(
            method: String(parts[0]),
            path: pieces.first ?? "/",
            query: pieces.count > 1 ? EvalRequest.decode(pieces[1]) : [:],
            body: String(decoding: body.prefix(length), as: UTF8.self)
        )
    }
}
