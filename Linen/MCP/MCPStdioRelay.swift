// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging
import MCP
import Network

actor MCPStdioRelay {
    private let socketPath: String
    private var clientName = "External Connection"
    private var backend: (client: MCP.Client, transport: LocalMCPTransport)?
    private var busy = false
    private var stopped = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func run(transport: any Transport) async throws {
        let server = MCP.Server(
            name: "Linen", version: "1.0.0", instructions: MCPToolCatalog.instructions,
            capabilities: .init(tools: .init()), configuration: .strict
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPToolCatalog.entries.map(\.tool))
        }
        await server.withMethodHandler(CallTool.self) { params in
            try await self.call(params)
        }
        do {
            try await server.start(transport: MCPRelayInput(transport)) { info, _ in
                await self.setClientName(info.name)
            }
            await server.waitUntilCompleted()
        } catch {
            await stop()
            await server.stop()
            throw error
        }
        await stop()
        await server.stop()
    }

    private func setClientName(_ name: String) {
        clientName = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(100))
    }

    private func stop() async {
        stopped = true
        let previous = backend
        backend = nil
        await previous?.client.disconnect()
    }

    private func call(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard !stopped else { throw MCPError.connectionClosed }
        guard let entry = MCPToolCatalog.entries.first(where: { $0.name == params.name }) else {
            throw MCPError.invalidParams("Unknown tool.")
        }
        try entry.validate(params.arguments ?? [:])
        guard !busy else { return failure("Another operation is running. Wait for its result.") }
        busy = true
        defer { busy = false }

        if let backend, !(await backend.transport.isConnected) {
            self.backend = nil
            await backend.client.disconnect()
        }
        guard !stopped, !Task.isCancelled else { throw CancellationError() }
        if backend == nil {
            let client = MCP.Client(name: clientName, version: "1.0.0")
            let transport = LocalMCPTransport(
                connection: NWConnection(to: .unix(path: socketPath), using: .tcp),
                onDisconnect: { await client.disconnect() }
            )
            backend = (client, transport)
            do {
                try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { _ = try await client.connect(transport: transport) }
                        group.addTask {
                            try await Task.sleep(for: .seconds(5))
                            await transport.disconnect()
                            await client.disconnect()
                            throw MCPError.connectionClosed
                        }
                        defer { group.cancelAll() }
                        _ = try await group.next()
                    }
                } onCancel: {
                    Task {
                        await transport.disconnect()
                        await client.disconnect()
                    }
                }
                guard !stopped, !Task.isCancelled else { throw CancellationError() }
            } catch {
                backend = nil
                await client.disconnect()
                await transport.disconnect()
                return failure("Linen is unavailable. Open Linen with MCP enabled, then retry. You do not need to restart the client.")
            }
        }
        guard let backend else { throw MCPError.connectionClosed }
        do {
            let request = try await backend.client.send(CallTool.request(params))
            return try await withTaskCancellationHandler {
                try await request.value
            } onCancel: {
                Task { await backend.client.disconnect() }
            }
        } catch {
            self.backend = nil
            await backend.client.disconnect()
            return failure("The Linen connection was interrupted. The operation may have completed; it was not retried. On your next call Linen will reconnect with no shared tabs. Request access again, then check the page before repeating an action.")
        }
    }

    private func failure(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }
}

private actor MCPRelayInput: Transport {
    nonisolated let logger = Logger(label: "Linen.mcp.relay", factory: { _ in SwiftLogNoOpLogHandler() })
    private let upstream: any Transport
    private let messages: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var reader: Task<Void, Never>?

    init(_ upstream: any Transport) {
        self.upstream = upstream
        (messages, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(64))
    }

    func connect() async throws {
        try await upstream.connect()
        reader = Task {
            do {
                for try await message in await upstream.receive() {
                    guard message.count <= MCPMessageFramer.maximumBytes else {
                        throw MCPError.invalidRequest("Message is too large.")
                    }
                    if case .dropped = continuation.yield(message) {
                        throw MCPError.invalidRequest("Too many pending messages.")
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func disconnect() async {
        reader?.cancel()
        reader = nil
        continuation.finish()
        await upstream.disconnect()
    }

    func send(_ data: Data) async throws { try await upstream.send(data) }
    func receive() -> AsyncThrowingStream<Data, any Error> { messages }
}
