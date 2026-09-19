// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import MCP
import Network

nonisolated enum LocalMCPEndpoint {
    static var directory: String {
        "/tmp/linen-mcp-\(geteuid())"
    }

    static var path: String {
        directory + "/browser.sock"
    }

    static func lockDirectory(_ directory: String) throws -> Int32 {
        guard mkdir(directory, 0o700) == 0 || errno == EEXIST else { throw failure() }
        var info = stat()
        guard lstat(directory, &info) == 0,
              info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o777 == 0o700
        else { throw failure() }
        let descriptor = open(directory + "/server.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw failure() }
        guard fstat(descriptor, &info) == 0,
              info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else {
            close(descriptor)
            throw failure()
        }
        return descriptor
    }

    static func failure() -> MCPError {
        .internalError("The local MCP endpoint is unavailable. Another copy of Linen may be using it.")
    }

    static func runStdioRelay(socketPath: String = path) -> Never {
        Task.detached {
            let relay = MCPStdioRelay(socketPath: socketPath)
            do {
                try await relay.run(transport: StdioTransport())
                exit(EXIT_SUCCESS)
            } catch {
                let message = "Linen MCP client connection closed.\n"
                try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }
}

@MainActor
final class LocalMCPListener {
    private let listener: NWListener
    private let lock: Int32
    private let path: String
    private var stopped = false

    init(path: String = LocalMCPEndpoint.path, accept: @escaping @MainActor (NWConnection) -> Void) throws {
        self.path = path
        lock = try LocalMCPEndpoint.lockDirectory(URL(fileURLWithPath: path).deletingLastPathComponent().path)
        unlink(path)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        do {
            listener = try NWListener(using: parameters)
        } catch {
            close(lock)
            throw error
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in accept(connection) }
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [listener, path] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if chmod(path, 0o600) == 0 {
                        ready.resume()
                    } else {
                        ready.resume(throwing: LocalMCPEndpoint.failure())
                    }
                case .failed(let error), .waiting(let error):
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "Linen.mcp.listener"))
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        listener.cancel()
        unlink(path)
        close(lock)
    }

    isolated deinit {
        stop()
    }
}
