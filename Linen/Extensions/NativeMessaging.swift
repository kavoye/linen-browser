// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import WebKit

// Chrome's exact runtime.lastError strings; extensions string-match them, never localize.
nonisolated enum NativeMessagingError: Error, Sendable, LocalizedError {
    case forbidden
    case communicationFailed
    case hostExited

    var errorDescription: String? {
        switch self {
        case .forbidden: "Access to the specified native messaging host is forbidden."
        case .communicationFailed: "Error when communicating with the native messaging host."
        case .hostExited: "Native host has exited."
        }
    }
}

nonisolated enum NativeMessageFraming {
    static let maxMessageBytes = 64 * 1024 * 1024

    static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxMessageBytes else { throw NativeMessagingError.communicationFailed }
        var frame = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }
}

nonisolated struct NativeMessageDecoder {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func next() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let base = buffer.startIndex
        let length = UInt32(buffer[base])
            | UInt32(buffer[base + 1]) << 8
            | UInt32(buffer[base + 2]) << 16
            | UInt32(buffer[base + 3]) << 24
        guard Int(length) <= NativeMessageFraming.maxMessageBytes else {
            throw NativeMessagingError.communicationFailed
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let payload = Data(buffer[(base + 4)..<(base + total)])
        buffer.removeSubrange(base..<(base + total))
        return payload
    }
}

nonisolated struct NativeMessagingManifest: Equatable, Sendable {
    var name: String
    var path: String
    var allowedOrigins: [String] = []
    var allowedExtensions: [String] = []
    var fileURL: URL?

    static var defaultSearchDirectories: [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return [
            library.appendingPathComponent("Linen/NativeMessagingHosts", isDirectory: true),
            library.appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true),
            library.appendingPathComponent("Chromium/NativeMessagingHosts", isDirectory: true),
            URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support/Chromium/NativeMessagingHosts", isDirectory: true),
        ]
    }

    static var defaultMozillaDirectories: [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return [
            library.appendingPathComponent("Mozilla/NativeMessagingHosts", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support/Mozilla/NativeMessagingHosts", isDirectory: true),
        ]
    }

    static func isValidHostName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }

    static func parse(_ data: Data, name: String) -> NativeMessagingManifest? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["name"] as? String == name,
              root["type"] as? String == "stdio",
              let path = root["path"] as? String
        else { return nil }
        let origins = root["allowed_origins"] as? [String] ?? []
        let extensions = root["allowed_extensions"] as? [String] ?? []
        guard !origins.isEmpty || !extensions.isEmpty else { return nil }
        return NativeMessagingManifest(
            name: name,
            path: path,
            allowedOrigins: origins,
            allowedExtensions: extensions
        )
    }

    static func locate(name: String, in directories: [URL]) -> NativeMessagingManifest? {
        guard isValidHostName(name) else { return nil }
        for directory in directories {
            let file = directory.appendingPathComponent("\(name).json")
            guard let data = try? Data(contentsOf: file),
                  var manifest = parse(data, name: name)
            else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: manifest.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: manifest.path)
            else { continue }
            manifest.fileURL = file
            return manifest
        }
        return nil
    }

    static func geckoID(inPackage package: URL) -> String? {
        let url = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let settings = (root["browser_specific_settings"] ?? root["applications"]) as? [String: Any]
        return (settings?["gecko"] as? [String: Any])?["id"] as? String
    }

    func allows(origin: String) -> Bool {
        let target = trimmed(origin)
        return allowedOrigins.contains { trimmed($0).caseInsensitiveCompare(target) == .orderedSame }
    }

    private func trimmed(_ origin: String) -> String {
        origin.hasSuffix("/") ? String(origin.dropLast()) : origin
    }
}

nonisolated final class NativeMessagingConnection: @unchecked Sendable {
    enum Event: Sendable {
        case message(Data)
        case closed(NativeMessagingError?)
    }

    let events: AsyncStream<Event>

    private let process = Process()
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let continuation: AsyncStream<Event>.Continuation
    private let queue = DispatchQueue(label: "com.kavoye.Linen.native-messaging")
    private var decoder = NativeMessageDecoder()
    private var finished = false
    private var exitStatus: Int32?
    private var sawEOF = false

    init(manifest: NativeMessagingManifest, arguments: [String]) throws {
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        stdinHandle = input.fileHandleForWriting
        stdoutHandle = output.fileHandleForReading
        stderrHandle = errors.fileHandleForReading

        let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        events = stream
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: manifest.path)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Writing to a dead host's stdin raises SIGPIPE and kills Linen without this.
        _ = fcntl(stdinHandle.fileDescriptor, F_SETNOSIGPIPE, 1)

        let hostName = manifest.name
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.queue.async { self.ingest(chunk) }
        }
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let text = String(decoding: chunk.prefix(512), as: UTF8.self)
            Pipeline.log.notice("nativemsg: \(hostName, privacy: .public) stderr: \(text, privacy: .public)")
        }
        // EOF and termination race in both orders; whichever lands second closes.
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            guard let self else { return }
            self.queue.async {
                self.exitStatus = status
                if status != 0 {
                    Pipeline.log.notice("nativemsg: \(hostName, privacy: .public) exited with \(status, privacy: .public)")
                }
                if self.sawEOF { self.finishForExit(status) }
            }
            self.queue.asyncAfter(deadline: .now() + 2) {
                self.finishForExit(status)
            }
        }

        do {
            try process.run()
        } catch {
            continuation.finish()
            Pipeline.log.error("nativemsg: \(hostName, privacy: .public) failed to launch: \(error, privacy: .public)")
            throw NativeMessagingError.communicationFailed
        }
    }

    func send(_ payload: Data) {
        queue.async { [weak self] in
            guard let self, !self.finished else { return }
            do {
                try self.stdinHandle.write(contentsOf: NativeMessageFraming.encode(payload))
            } catch {
                self.finish(.closed(.hostExited))
            }
        }
    }

    func close() {
        queue.async { [weak self] in self?.finish(.closed(nil)) }
    }

    private func ingest(_ chunk: Data) {
        guard !finished else { return }
        guard !chunk.isEmpty else {
            sawEOF = true
            if let exitStatus { finishForExit(exitStatus) }
            return
        }
        decoder.append(chunk)
        do {
            while let payload = try decoder.next() {
                continuation.yield(.message(payload))
            }
        } catch {
            finish(.closed(.communicationFailed))
        }
    }

    private func finishForExit(_ status: Int32) {
        finish(.closed(status != 0 ? .hostExited : nil))
    }

    private func finish(_ event: Event) {
        guard !finished else { return }
        finished = true
        continuation.yield(event)
        continuation.finish()
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdinHandle.close()
        let process = process
        if process.isRunning {
            queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

@MainActor
final class NativeMessagingService {
    enum ConnectOutcome {
        case unavailable
        case connected
        case failed(any Error)
    }

    private enum Resolution {
        case host(NativeMessagingManifest, arguments: [String])
        case unavailable
        case forbidden
    }

    private let searchDirectories: [URL]
    private let mozillaDirectories: [URL]
    var geckoID: ((String) -> String?)?
    private var connections: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(
        searchDirectories: [URL] = NativeMessagingManifest.defaultSearchDirectories,
        mozillaDirectories: [URL] = NativeMessagingManifest.defaultMozillaDirectories
    ) {
        self.searchDirectories = searchDirectories
        self.mozillaDirectories = mozillaDirectories
    }

    private func resolve(
        _ applicationIdentifier: String?,
        for context: WKWebExtensionContext
    ) -> Resolution {
        guard let name = applicationIdentifier,
              NativeMessagingManifest.isValidHostName(name),
              context.hasPermission(.nativeMessaging)
        else { return .unavailable }

        var refused = false
        if let manifest = NativeMessagingManifest.locate(name: name, in: searchDirectories) {
            let origin = "chrome-extension://\(context.uniqueIdentifier)/"
            if manifest.allows(origin: origin) {
                return .host(manifest, arguments: [origin])
            }
            refused = true
        }
        if let gecko = geckoID?(context.uniqueIdentifier),
           let manifest = NativeMessagingManifest.locate(name: name, in: mozillaDirectories) {
            if manifest.allowedExtensions.contains(gecko) {
                return .host(manifest, arguments: [manifest.fileURL?.path ?? name, gecko])
            }
            refused = true
        }
        guard refused else { return .unavailable }
        Pipeline.log.notice("""
            nativemsg: \(name, privacy: .public) refuses \
            \(context.uniqueIdentifier, privacy: .public)
            """)
        return .forbidden
    }

    func connect(port: WKWebExtension.MessagePort, for context: WKWebExtensionContext) -> ConnectOutcome {
        let manifest: NativeMessagingManifest
        let arguments: [String]
        switch resolve(port.applicationIdentifier, for: context) {
        case .unavailable:
            return .unavailable
        case .forbidden:
            return .failed(NativeMessagingError.forbidden)
        case .host(let found, let foundArguments):
            (manifest, arguments) = (found, foundArguments)
        }

        let connection: NativeMessagingConnection
        do {
            connection = try NativeMessagingConnection(manifest: manifest, arguments: arguments)
        } catch {
            return .failed(error)
        }

        port.messageHandler = { [weak connection] message, error in
            guard let connection else { return }
            guard error == nil else {
                connection.close()
                return
            }
            guard let message,
                  let data = try? JSONSerialization.data(withJSONObject: message, options: .fragmentsAllowed)
            else {
                Pipeline.log.error("nativemsg: dropped a message that would not encode")
                return
            }
            connection.send(data)
        }
        port.disconnectHandler = { [weak connection] _ in
            connection?.close()
        }

        let key = ObjectIdentifier(port)
        connections[key] = Task { @MainActor [weak self] in
            for await event in connection.events {
                switch event {
                case .message(let data):
                    guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
                        continue
                    }
                    try? await port.sendMessage(object)
                case .closed(let error):
                    port.disconnect(throwing: error.map { $0 as NSError })
                }
            }
            self?.connections[key] = nil
        }
        Pipeline.log.notice("""
            nativemsg: connected \(context.uniqueIdentifier, privacy: .public) → \
            \(manifest.name, privacy: .public)
            """)
        return .connected
    }

    func sendOnce(
        message: Any,
        applicationIdentifier: String?,
        for context: WKWebExtensionContext,
        reply: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        let manifest: NativeMessagingManifest
        let arguments: [String]
        switch resolve(applicationIdentifier, for: context) {
        case .unavailable:
            return false
        case .forbidden:
            reply(nil, NativeMessagingError.forbidden)
            return true
        case .host(let found, let foundArguments):
            (manifest, arguments) = (found, foundArguments)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: message, options: .fragmentsAllowed) else {
            reply(nil, NativeMessagingError.communicationFailed)
            return true
        }
        let connection: NativeMessagingConnection
        do {
            connection = try NativeMessagingConnection(manifest: manifest, arguments: arguments)
        } catch {
            reply(nil, error)
            return true
        }
        connection.send(data)
        Task { @MainActor in
            for await event in connection.events {
                switch event {
                case .message(let payload):
                    let object = try? JSONSerialization.jsonObject(with: payload, options: .fragmentsAllowed)
                    reply(object, nil)
                    connection.close()
                    return
                case .closed(let error):
                    reply(nil, error ?? NativeMessagingError.hostExited)
                    return
                }
            }
        }
        return true
    }
}
