// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

nonisolated enum MCPCodexConfiguration {
    private static func withStagedConfiguration<T>(_ original: Data?, body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appending(path: "linen-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = directory.appending(path: "config.toml")
        if let original {
            try MCPConfigurationFile.writePrivate(original, to: configuration)
        }
        return try body(directory)
    }

    static func isInstalled(in original: Data?, executable: URL, command: String) throws -> Bool {
        guard original != nil else { return false }
        return try withStagedConfiguration(original) { directory in
            let entries = try servers(executable: executable, directory: directory)
            guard let existing = entries.first(where: { $0["name"] as? String == "linen" }) else { return false }
            guard let transport = existing["transport"] as? [String: Any],
                  MCPClientConfiguration.matches(transport, command: command) else { throw MCPClientSetupError.conflictingServer }
            return true
        }
    }

    static func adding(to original: Data?, executable: URL, command: String) throws -> Data? {
        try withStagedConfiguration(original) { directory in
            try addInStagingDirectory(directory, executable: executable, command: command)
        }
    }

    private static func addInStagingDirectory(_ directory: URL, executable: URL, command: String) throws -> Data? {
        let configuration = directory.appending(path: "config.toml")
        let before = try servers(executable: executable, directory: directory)
        if let existing = before.first(where: { $0["name"] as? String == "linen" }) {
            guard let transport = existing["transport"] as? [String: Any],
                  MCPClientConfiguration.matches(transport, command: command) else { throw MCPClientSetupError.conflictingServer }
            return nil
        }
        _ = try run(executable, arguments: ["mcp", "add", "linen", "--", command, "--mcp"], directory: directory)
        let after = try servers(executable: executable, directory: directory)
        guard let installed = after.first(where: { $0["name"] as? String == "linen" })?["transport"] as? [String: Any],
              MCPClientConfiguration.matches(installed, command: command),
              NSDictionary(dictionary: indexed(before)).isEqual(to: indexed(after.filter { $0["name"] as? String != "linen" })) else {
            throw MCPClientSetupError.commandFailed
        }
        return try MCPConfigurationFile(url: configuration).original
    }

    private static func indexed(_ entries: [[String: Any]]) -> [String: Any] {
        var result: [String: Any] = [:]
        for entry in entries {
            if let name = entry["name"] as? String { result[name] = entry }
        }
        return result
    }

    private static func servers(executable: URL, directory: URL) throws -> [[String: Any]] {
        let data = try run(executable, arguments: ["mcp", "list", "--json"], directory: directory)
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw MCPClientSetupError.commandFailed
        }
        return entries
    }

    private static func run(_ executable: URL, arguments: [String], directory: URL) throws -> Data {
        let output = directory.appending(path: "output-\(UUID().uuidString)")
        try MCPConfigurationFile.writePrivate(Data(), to: output)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = directory.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while process.isRunning {
            if ContinuousClock.now >= deadline || Task.isCancelled {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                throw MCPClientSetupError.commandFailed
            }
            usleep(10_000)
        }
        guard process.terminationStatus == 0 else { throw MCPClientSetupError.commandFailed }
        return try MCPConfigurationFile(url: output).original ?? Data()
    }
}
