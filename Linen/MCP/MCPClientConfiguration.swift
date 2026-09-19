// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

nonisolated enum MCPClientKind: String, CaseIterable, Identifiable, Sendable {
    case codex, claudeDesktop, claudeCode, cursor

    var id: Self {
        self
    }

    var name: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeDesktop:
            "Claude Desktop"
        case .claudeCode:
            "Claude Code"
        case .cursor:
            "Cursor"
        }
    }

    func configurationURL(home: URL, environment: [String: String]) -> URL {
        switch self {
        case .codex:
            if let path = environment["CODEX_HOME"], path.hasPrefix("/") {
                return URL(fileURLWithPath: path).appending(path: "config.toml")
            }
            return home.appending(path: ".codex/config.toml")
        case .claudeDesktop:
            return home.appending(path: "Library/Application Support/Claude/claude_desktop_config.json")
        case .claudeCode:
            return home.appending(path: ".claude.json")
        case .cursor:
            return home.appending(path: ".cursor/mcp.json")
        }
    }
}

nonisolated struct MCPClientTarget: Identifiable, Sendable {
    let kind: MCPClientKind
    var configurationURL: URL
    let codexExecutable: URL?
    let isDetected: Bool

    var id: MCPClientKind {
        kind
    }
}

enum MCPClientDiscovery {
    static func targets(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [MCPClientTarget] {
        let codexApps = ["com.openai.codex", "com.openai.chat"].compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        let appRoots = [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")]
        let bundled = (codexApps + appRoots.flatMap { root in
            [root.appending(path: "Codex.app"), root.appending(path: "ChatGPT.app")]
        }).map { $0.appending(path: "Contents/Resources/codex") }
        let codex = executable(named: "codex", home: home, environment: environment)
            ?? bundled.first { FileManager.default.isExecutableFile(atPath: $0.path) }

        return MCPClientKind.allCases.map { kind in
            let url = kind.configurationURL(home: home, environment: environment)
            let installed: Bool
            switch kind {
            case .codex:
                installed = codex != nil
            case .claudeCode:
                installed = executable(named: "claude", home: home, environment: environment) != nil
            case .claudeDesktop:
                installed = appRoots.contains { FileManager.default.fileExists(atPath: $0.appending(path: "Claude.app").path) }
                    || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
            case .cursor:
                installed = appRoots.contains { FileManager.default.fileExists(atPath: $0.appending(path: "Cursor.app").path) }
                    || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil
            }
            return MCPClientTarget(kind: kind, configurationURL: url, codexExecutable: codex,
                                   isDetected: installed || FileManager.default.fileExists(atPath: url.path))
        }
    }

    private static func executable(named name: String, home: URL, environment: [String: String]) -> URL? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appending(path: ".local/bin").path, home.appending(path: ".npm-global/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin", ]
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appending(path: name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

nonisolated enum MCPClientSetupError: Error, LocalizedError {
    case invalidConfiguration, conflictingServer, unsafeFile, changedFile, missingCodex, commandFailed, fileAccess

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            String(localized: "The configuration could not be read. Fix its format or use Copy Configuration.")
        case .conflictingServer:
            String(localized: "A different server named linen is already configured. Review that entry in the client before adding Linen.")
        case .unsafeFile:
            String(localized: "Choose a regular configuration file owned by you. Linked files are not changed automatically.")
        case .changedFile:
            String(localized: "The client changed its configuration during setup. Try again after closing the client.")
        case .missingCodex:
            String(localized: "Install Codex or its command-line tool to add Linen automatically. You can also use Copy Configuration.")
        case .commandFailed:
            String(localized: "Codex could not update the configuration. Check it in Codex or use Copy Configuration.")
        case .fileAccess:
            String(localized: "Linen couldn’t save the configuration. Check the file’s permissions and try again.")
        }
    }
}

nonisolated enum MCPClientConfiguration {
    static var command: String {
        Bundle.main.executableURL?.path ?? "/Applications/Linen.app/Contents/MacOS/Linen"
    }

    static func entry(command: String, kind: MCPClientKind) -> [String: Any] {
        var value: [String: Any] = ["command": command, "args": ["--mcp"]]
        if kind == .claudeCode { value["type"] = "stdio" }
        return value
    }

    static func matches(_ entry: [String: Any], command: String) -> Bool {
        entry["command"] as? String == command && entry["args"] as? [String] == ["--mcp"]
            && entry["url"] == nil && (entry["type"] == nil || entry["type"] as? String == "stdio")
    }

    static func addingJSON(to data: Data?, kind: MCPClientKind, command: String) throws -> Data? {
        var root: [String: Any] = [:]
        if let data {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPClientSetupError.invalidConfiguration
            }
            root = parsed
        }
        var servers: [String: Any] = [:]
        if let existing = root["mcpServers"] {
            guard let dictionary = existing as? [String: Any] else { throw MCPClientSetupError.invalidConfiguration }
            servers = dictionary
        }
        if let existing = servers["linen"] {
            guard let entry = existing as? [String: Any], matches(entry, command: command) else {
                throw MCPClientSetupError.conflictingServer
            }
            return nil
        }
        servers["linen"] = entry(command: command, kind: kind)
        root["mcpServers"] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data([10])
    }
}
