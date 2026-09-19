// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import MCP
import Network
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct MCPTransportTests {
    @Test(.timeLimit(.minutes(1))) func relayCanStartBeforeBrowserAndRecoverAfterItLaunches() async throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let endpoint = directory + "/browser.sock"
        let pair = await InMemoryTransport.createConnectedPair()
        try await pair.server.connect()
        let relay = MCPStdioRelay(socketPath: endpoint)
        let running = Task { try await relay.run(transport: pair.server) }
        defer { Task { await pair.client.disconnect() } }
        let client = MCP.Client(name: "Offline startup", version: "1")
        _ = try await client.connect(transport: pair.client)
        let (tools, _) = try await client.listTools()
        #expect(!tools.isEmpty)
        let (_, offline) = try await client.callTool(name: "listTabs")
        #expect(offline == true)
        let server = BrowserMCPServer(browser: BrowserModel(database: .temporary()), endpoint: endpoint, available: { true })
        defer { server.stop() }
        server.setEnabled(true)
        #expect(await waitUntil { server.isListening })
        let (_, recovered) = try await client.callTool(name: "listTabs")
        #expect(recovered == false)
        await client.disconnect()
        try await running.value
        #expect(await waitUntil { server.sessions.isEmpty })
    }

    @Test(.timeLimit(.minutes(1))) func relayFailsInterruptedActionsWithoutReplayingThem() async throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let endpoint = directory + "/browser.sock"
        let probe = SuspendedRelayCall()
        let backend = MCP.Server(name: "Fixture", version: "1", capabilities: .init(tools: .init()))
        await backend.withMethodHandler(CallTool.self) { _ in await probe.call() }
        var socket: LocalMCPTransport?
        let listener = try LocalMCPListener(path: endpoint) { connection in
            let transport = LocalMCPTransport(connection: connection)
            socket = transport
            Task {
                do {
                    try await backend.start(transport: transport)
                } catch {
                    Issue.record(error)
                    await transport.disconnect()
                }
            }
        }
        defer {
            listener.stop()
            Task { await probe.release(); await backend.stop() }
        }
        try await listener.start()
        let pair = await InMemoryTransport.createConnectedPair()
        try await pair.server.connect()
        let relay = MCPStdioRelay(socketPath: endpoint)
        let running = Task { try await relay.run(transport: pair.server) }
        defer { Task { await pair.client.disconnect() } }
        let client = MCP.Client(name: "Interrupted action", version: "1")
        _ = try await client.connect(transport: pair.client)
        let action = Task { try await client.callTool(name: "scrollPage", arguments: ["tabID": "fixture", "direction": "down"]) }
        #expect(await waitUntil { await probe.count == 1 })
        await socket?.disconnect()
        let (content, failed) = try await action.value
        #expect(failed == true)
        #expect(content.contains { if case .text(let text, _, _) = $0 { return text.contains("was not retried") }; return false })
        let (tools, _) = try await client.listTools()
        #expect(!tools.isEmpty)
        #expect(await probe.count == 1)
        await probe.release()
        await client.disconnect()
        try await running.value
    }

    @Test func enablementSurvivesShutdownAndExplicitDisablePersists() async throws {
        let name = "linen-mcp-preference-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(atPath: directory)
        }
        let browser = BrowserModel(database: .temporary())
        let server = BrowserMCPServer(browser: browser, endpoint: directory + "/browser.sock", defaults: defaults, available: { true })
        #expect(!server.isEnabled)
        server.setEnabled(true)
        #expect(await waitUntil { server.isListening })
        server.stop()
        #expect(server.isEnabled)
        #expect(!server.isListening)

        let relaunched = BrowserMCPServer(browser: browser, endpoint: directory + "/browser.sock", defaults: defaults, available: { true })
        defer { relaunched.stop() }
        #expect(relaunched.isEnabled)
        relaunched.resume()
        #expect(await waitUntil { relaunched.isListening })
        relaunched.setEnabled(false)
        let disabled = BrowserMCPServer(browser: browser, defaults: defaults, available: { true })
        #expect(!disabled.isEnabled)
    }

    @Test func privateBrowsingPausesWithoutDisablingAndRevokesConnections() async throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        var isPrivate = false
        let server = BrowserMCPServer(browser: BrowserModel(database: .temporary()), endpoint: directory + "/browser.sock") { !isPrivate }
        defer { server.stop() }
        server.setEnabled(true)
        #expect(await waitUntil { server.isListening })
        let client = MCP.Client(name: "Profile test", version: "1")
        let transport = LocalMCPTransport(connection: NWConnection(to: .unix(path: directory + "/browser.sock"), using: .tcp))
        _ = try await client.connect(transport: transport)
        let session = try #require(server.sessions.first)

        isPrivate = true
        server.stop()
        server.resume()
        #expect(server.isEnabled)
        #expect(server.isPaused)
        #expect(!server.isListening)
        #expect(!session.isConnected)
        #expect(server.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory + "/browser.sock"))

        isPrivate = false
        server.resume()
        #expect(await waitUntil { server.isListening })
        #expect(server.isEnabled)
        #expect(!server.isPaused)
        #expect(server.sessions.isEmpty)
        await transport.disconnect()
    }

    @Test func partialAndCoalescedMessagesKeepTheirBoundaries() throws {
        var framer = MCPMessageFramer()
        #expect(try framer.append(Data("{\"id\":".utf8)).isEmpty)
        let messages = try framer.append(Data("1}\n{\"id\":2}\n\n".utf8))
        #expect(messages.map { String(decoding: $0, as: UTF8.self) } == ["{\"id\":1}", "{\"id\":2}"])
    }

    @Test func overlongMessagesAreRejectedBeforeDispatch() {
        var framer = MCPMessageFramer()
        #expect(throws: (any Error).self) {
            _ = try framer.append(Data(repeating: 65, count: MCPMessageFramer.maximumBytes + 1))
        }
        var complete = MCPMessageFramer()
        #expect(throws: (any Error).self) {
            _ = try complete.append(Data(repeating: 65, count: MCPMessageFramer.maximumBytes + 1) + Data([10]))
        }
    }

    @Test func argumentValidationRejectsCoercionAndUnknownFields() throws {
        let click = try #require(MCPToolCatalog.entries.first { $0.name == "clickOnPage" })
        #expect(throws: (any Error).self) {
            try click.validate(["tabID": "tab", "observationID": "observation", "ref": "1"])
        }
        #expect(throws: (any Error).self) {
            try click.validate(["tabID": "tab", "observationID": "observation", "ref": 1, "bypass": true])
        }
        #expect(throws: (any Error).self) {
            try click.validate(["tabID": "tab", "observationID": "observation", "ref": 0])
        }
    }

    @Test func endpointRejectsInsecureDirectoriesAndCompetingListeners() throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(mkdir(directory, 0o755) == 0)
        #expect(throws: (any Error).self) {
            _ = try LocalMCPEndpoint.lockDirectory(directory)
        }
        #expect(chmod(directory, 0o700) == 0)
        let lock = try LocalMCPEndpoint.lockDirectory(directory)
        defer { close(lock) }
        #expect(throws: (any Error).self) {
            _ = try LocalMCPEndpoint.lockDirectory(directory)
        }
    }

    @Test func standardClientCanDiscoverToolsWithoutBrowserAccess() async throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        let endpoint = directory + "/browser.sock"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let browser = BrowserModel(database: .temporary())
        let server = BrowserMCPServer(browser: browser, endpoint: endpoint, available: { true })
        defer { server.stop() }
        server.setEnabled(true)
        #expect(await waitUntil { server.isListening || server.status != nil })
        #expect(server.isListening, "\(server.status ?? "No status")")
        var info = stat()
        #expect(lstat(endpoint, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)

        let client = MCP.Client(name: "Integration test", version: "1")
        let transport = LocalMCPTransport(connection: NWConnection(to: .unix(path: endpoint), using: .tcp))
        let initialized = try await client.connect(transport: transport)
        #expect(initialized.capabilities.tools != nil)
        let (tools, _) = try await client.listTools()
        #expect(Set(tools.map(\.name)) == Set(MCPToolCatalog.entries.map(\.name)))
        let (content, isError) = try await client.callTool(name: "listTabs")
        #expect(isError == false)
        #expect(content == [.text(text: "{\"tabs\":[]}", annotations: nil, _meta: nil)])
        #expect(await waitUntil { server.sessions.first?.clientName == "Integration test" })
        let session = try #require(server.sessions.first)
        server.stop()
        #expect(!session.isConnected)
        #expect(server.sessions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: endpoint))
        await transport.disconnect()
    }

    @Test(.timeLimit(.minutes(1))) func bundledStdioRelaySurvivesBrowserRestartAndExitsOnEOF() async throws {
        let directory = "/tmp/linen-mcp-test-\(UUID().uuidString)"
        let endpoint = directory + "/browser.sock"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let server = BrowserMCPServer(browser: BrowserModel(database: .temporary()), endpoint: endpoint, available: { true })
        defer { server.stop() }
        server.setEnabled(true)
        #expect(await waitUntil { server.isListening || server.status != nil })
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--mcp", "--mcp-socket", endpoint]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }
        let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"Stdio integration","version":"1"}}}"#
        try input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))
        let (lines, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let read = Task.detached {
            var line = Data()
            do {
                for try await byte in output.fileHandleForReading.bytes {
                    if byte == 10 {
                        continuation.yield(line)
                        line = Data()
                    } else {
                        line.append(byte)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        defer { read.cancel() }
        var replies = lines.makeAsyncIterator()
        let reply = try #require(await replies.next())
        let object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        #expect(object["id"] as? Int == 1)
        #expect(object["result"] != nil)
        try input.fileHandleForWriting.write(contentsOf: Data((#"{"jsonrpc":"2.0","method":"notifications/initialized"}"# + "\n").utf8))
        func send(_ id: Int, _ tool: String) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": tool],
            ])
            try input.fileHandleForWriting.write(contentsOf: data + Data([10]))
        }
        try send(2, "listTabs")
        let first = try #require(await replies.next())
        #expect(String(decoding: first, as: UTF8.self).contains("structuredContent"))
        let originalSession = try #require(server.sessions.first)
        #expect(originalSession.clientName == "Stdio integration")

        server.stop()
        #expect(!originalSession.isConnected)
        try send(3, "listTabs")
        let offline = try #require(await replies.next())
        #expect(String(decoding: offline, as: UTF8.self).contains("\"isError\":true"))
        #expect(process.isRunning)

        server.resume()
        #expect(await waitUntil { server.isListening })
        try send(4, "listTabs")
        let recovered = try #require(await replies.next())
        let recoveredObject = try #require(JSONSerialization.jsonObject(with: recovered) as? [String: Any])
        let result = try #require(recoveredObject["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let structured = try #require(result["structuredContent"] as? [String: Any])
        #expect((structured["tabs"] as? [Any])?.isEmpty == true)
        let freshSession = try #require(server.sessions.first)
        #expect(freshSession.id != originalSession.id)
        #expect(freshSession.grants.isEmpty)
        #expect(freshSession.clientName == "Stdio integration")
        try input.fileHandleForWriting.close()
        #expect(await waitUntil { !process.isRunning })
        #expect(process.terminationStatus == 0)
        #expect(await waitUntil { server.sessions.isEmpty })
    }
}

private actor SuspendedRelayCall {
    private(set) var count = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func call() async -> CallTool.Result {
        count += 1
        await withCheckedContinuation { continuation = $0 }
        return CallTool.Result(content: [], isError: false)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
