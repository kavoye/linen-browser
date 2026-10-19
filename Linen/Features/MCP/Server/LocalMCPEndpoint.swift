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
                try await relay.run(transport: MCPStdioTransport())
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
    private let socket: Int32
    private let lock: Int32
    private let path: String
    private let accept: @MainActor (Int32, MCPClientIdentity?) -> Void
    private var source: DispatchSourceRead?
    private var stopped = false

    init(path: String = LocalMCPEndpoint.path, accept: @escaping @MainActor (Int32, MCPClientIdentity?) -> Void) throws {
        self.path = path
        self.accept = accept
        lock = try LocalMCPEndpoint.lockDirectory(URL(fileURLWithPath: path).deletingLastPathComponent().path)
        unlink(path)
        socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            close(lock)
            throw LocalMCPEndpoint.failure()
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            close(socket)
            close(lock)
            throw LocalMCPEndpoint.failure()
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(socket, 8) == 0,
              fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK) == 0
        else {
            close(socket)
            unlink(path)
            close(lock)
            throw LocalMCPEndpoint.failure()
        }
        _ = fcntl(socket, F_SETFD, FD_CLOEXEC)
    }

    func start() async throws {
        guard source == nil, !stopped else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.acceptPending()
            }
        }
        self.source = source
        source.resume()
    }

    private func acceptPending() {
        while !stopped {
            let client = Darwin.accept(socket, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            var on: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            accept(client, MCPClientIdentity.ofPeer(socket: client))
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        source?.cancel()
        source = nil
        close(socket)
        unlink(path)
        close(lock)
    }

    isolated deinit {
        stop()
    }
}
