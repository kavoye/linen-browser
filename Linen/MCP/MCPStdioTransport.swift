// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Logging
import MCP

/// Dispatch waits for pipe activity instead of polling idle stdin every 10 ms.
actor MCPStdioTransport: Transport {
    nonisolated let logger = Logger(label: "Linen.mcp.stdio", factory: { _ in SwiftLogNoOpLogHandler() })
    private let input: Int32
    private let output: Int32
    private let queue = DispatchQueue(label: "Linen.mcp.stdio")
    private let messages: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var inputChannel: DispatchIO?
    private var outputChannel: DispatchIO?
    private var reader: Task<Void, Never>?
    private var closed = false

    init(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO) {
        self.input = input
        self.output = output
        (messages, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(64))
    }

    func connect() throws {
        guard !closed else { throw MCPError.connectionClosed }
        guard inputChannel == nil else { return }
        let incoming = try channel(for: input)
        let outgoing: DispatchIO
        do {
            outgoing = try channel(for: output)
        } catch {
            incoming.close(flags: .stop)
            throw error
        }
        inputChannel = incoming
        outputChannel = outgoing
        incoming.setLimit(lowWater: 1)
        incoming.setLimit(highWater: 16_384)
        let (chunks, received) = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        incoming.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
            if let data, !data.isEmpty,
               case .dropped = received.yield(Data(data)) {
                received.finish(throwing: MCPError.invalidRequest("Too many pending messages."))
                return
            }
            if error != 0 {
                received.finish(throwing: Self.failure(error))
            } else if done {
                received.finish()
            }
        }
        reader = Task { [weak self] in
            var frames = MCPMessageFramer()
            do {
                for try await chunk in chunks {
                    guard let self else { return }
                    for message in try frames.append(chunk) {
                        if case .dropped = continuation.yield(message) {
                            throw MCPError.invalidRequest("Too many pending messages.")
                        }
                    }
                }
            } catch {
                self?.continuation.finish(throwing: error)
            }
            await self?.disconnect()
        }
    }

    func disconnect() {
        closed = true
        reader?.cancel()
        reader = nil
        inputChannel?.close(flags: .stop)
        outputChannel?.close(flags: .stop)
        inputChannel = nil
        outputChannel = nil
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        guard let outputChannel, !closed else { throw MCPError.connectionClosed }
        var framed = data
        framed.append(10)
        let bytes = framed.withUnsafeBytes { DispatchData(bytes: $0) }
        try await withCheckedThrowingContinuation { (sent: CheckedContinuation<Void, any Error>) in
            outputChannel.write(offset: 0, data: bytes, queue: queue) { done, _, error in
                guard done else { return }
                if error != 0 {
                    sent.resume(throwing: Self.failure(error))
                } else {
                    sent.resume()
                }
            }
        }
    }

    func receive() -> AsyncThrowingStream<Data, any Error> {
        messages
    }

    private func channel(for descriptor: Int32) throws -> DispatchIO {
        let owned = dup(descriptor)
        guard owned >= 0 else { throw Self.failure(errno) }
        return DispatchIO(type: .stream, fileDescriptor: owned, queue: queue) { _ in
            Darwin.close(owned)
        }
    }

    private nonisolated static func failure(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    deinit {
        reader?.cancel()
        inputChannel?.close(flags: .stop)
        outputChannel?.close(flags: .stop)
        continuation.finish()
    }
}
