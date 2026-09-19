// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging
import MCP
import Network

actor LocalMCPTransport: Transport {
    nonisolated let logger = Logger(label: "Linen.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "Linen.mcp.connection")
    private let messages: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var reader: Task<Void, Never>?
    private var connected = false
    private let onDisconnect: (@Sendable () async -> Void)?

    var isConnected: Bool {
        connected
    }

    init(connection: NWConnection, onDisconnect: (@Sendable () async -> Void)? = nil) {
        self.connection = connection
        self.onDisconnect = onDisconnect
        (messages, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(64))
    }

    func connect() async throws {
        guard !connected else { return }
        connected = true
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    ready.resume()
                case .failed(let error), .waiting(let error):
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    ready.resume(throwing: error)
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    ready.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        reader = Task { await readMessages() }
    }

    func disconnect() {
        let wasConnected = connected
        connected = false
        reader?.cancel()
        reader = nil
        connection.cancel()
        continuation.finish(throwing: MCPError.connectionClosed)
        if wasConnected, let onDisconnect {
            Task { await onDisconnect() }
        }
    }

    func send(_ data: Data) async throws {
        guard connected else { throw MCPError.connectionClosed }
        var framed = data
        framed.append(10)
        try await withCheckedThrowingContinuation { (sent: CheckedContinuation<Void, any Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    sent.resume(throwing: error)
                } else {
                    sent.resume()
                }
            })
        }
    }

    func receive() -> AsyncThrowingStream<Data, any Error> {
        messages
    }

    private func readMessages() async {
        var frames = MCPMessageFramer()
        do {
            while connected, !Task.isCancelled {
                let data = try await readChunk()
                guard let data else { break }
                for message in try frames.append(data) {
                    if case .dropped = continuation.yield(message) {
                        throw MCPError.invalidRequest("Too many pending messages.")
                    }
                }
            }
            continuation.finish(throwing: MCPError.connectionClosed)
        } catch {
            continuation.finish(throwing: error)
        }
        disconnect()
    }

    private func readChunk() async throws -> Data? {
        try await withCheckedThrowingContinuation { received in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
                if let error {
                    received.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    received.resume(returning: data)
                } else if complete {
                    received.resume(returning: nil)
                } else {
                    received.resume(returning: Data())
                }
            }
        }
    }
}

nonisolated struct MCPMessageFramer {
    static let maximumBytes = 262_144
    private var pending = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        pending.append(data)
        var messages: [Data] = []
        while let newline = pending.firstIndex(of: 10) {
            guard pending.distance(from: pending.startIndex, to: newline) <= Self.maximumBytes else {
                throw MCPError.invalidRequest("Message is too large.")
            }
            let message = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if !message.isEmpty {
                messages.append(message)
            }
        }
        guard pending.count <= Self.maximumBytes else {
            throw MCPError.invalidRequest("Message is too large.")
        }
        return messages
    }
}
