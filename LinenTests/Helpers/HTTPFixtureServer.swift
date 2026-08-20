// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network

/// A loopback HTTP server for WebKit integration tests. Routes are fixed so
/// tests cannot depend on the public network or a live service.
/// Network callbacks stay on `queue`; all state read by them is immutable.
nonisolated final class HTTPFixtureServer: @unchecked Sendable {
    struct Response: Sendable {
        let status: String
        let headers: [String: String]
        let body: Data
        /// Seconds to sit on the request before answering, so a test can hold
        /// a navigation in its provisional state.
        var delay: TimeInterval = 0

        static func html(
            _ body: String,
            headers additionalHeaders: [String: String] = [:],
            delay: TimeInterval = 0
        ) -> Response {
            var headers = additionalHeaders
            headers["Content-Type"] = "text/html; charset=utf-8"
            return Response(
                status: "200 OK",
                headers: headers,
                body: Data(body.utf8),
                delay: delay
            )
        }

        static func bytes(_ body: Data, contentType: String) -> Response {
            Response(
                status: "200 OK",
                headers: ["Content-Type": contentType],
                body: body
            )
        }

        static func download(_ body: Data, filename: String) -> Response {
            Response(
                status: "200 OK",
                headers: [
                    "Content-Disposition": "attachment; filename=\"\(filename)\"",
                    "Content-Type": "application/octet-stream",
                ],
                body: body
            )
        }

        static func redirect(to url: URL) -> Response {
            Response(status: "302 Found", headers: ["Location": url.absoluteString], body: Data())
        }

        fileprivate var encoded: Data {
            var fields = headers
            fields["Content-Length"] = String(body.count)
            fields["Connection"] = "close"
            let head = (["HTTP/1.1 \(status)"] + fields.map { "\($0): \($1)" })
                .joined(separator: "\r\n") + "\r\n\r\n"
            return Data(head.utf8) + body
        }
    }

    enum StartError: Error {
        case cancelled
        case invalidURL
        case missingPort
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "Linen.tests.http-fixture")
    private let routes: [String: Response]

    private init(listener: NWListener, routes: [String: Response]) {
        self.listener = listener
        self.routes = routes
    }

    deinit {
        listener.cancel()
    }

    static func start(routes: [String: Response]) async throws -> HTTPFixtureServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = HTTPFixtureServer(listener: listener, routes: routes)
        listener.newConnectionHandler = { [weak server] connection in
            server?.accept(connection)
        }

        try await withCheckedThrowingContinuation { continuation in
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
                    continuation.resume(throwing: StartError.cancelled)
                default:
                    break
                }
            }
            listener.start(queue: server.queue)
        }
        guard listener.port != nil else { throw StartError.missingPort }
        return server
    }

    func url(_ path: String = "/") throws -> URL {
        guard let port = listener.port else { throw StartError.missingPort }
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(path)") else {
            throw StartError.invalidURL
        }
        return url
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulated: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var request = accumulated
            if let data {
                request.append(data)
            }
            let hasHeaders = request.range(of: Data("\r\n\r\n".utf8)) != nil
            guard hasHeaders || complete || error != nil else {
                receiveRequest(from: connection, accumulated: request)
                return
            }
            sendResponse(for: request, over: connection)
        }
    }

    private func sendResponse(for request: Data, over connection: NWConnection) {
        let line = String(decoding: request, as: UTF8.self)
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let parts = line.split(separator: " ")
        let target = parts.count > 1 ? String(parts[1]) : "/"
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let response = routes[path] ?? Response(
            status: "404 Not Found",
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data("<h1>Not found</h1>".utf8)
        )
        let send = { @Sendable in
            connection.send(content: response.encoded, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
        if response.delay > 0 {
            queue.asyncAfter(deadline: .now() + response.delay, execute: send)
        } else {
            send()
        }
    }
}
