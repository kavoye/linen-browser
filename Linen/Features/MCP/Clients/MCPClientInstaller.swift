// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

actor MCPClientInstaller {
    struct Result: Sendable {
        let alreadyPresent: Bool
        let backupURL: URL?
    }

    func isInstalled(_ target: MCPClientTarget, command: String) throws -> Bool {
        do {
            let file = try MCPConfigurationFile(url: target.configurationURL)
            guard file.original != nil else { return false }
            if target.kind == .codex {
                guard let executable = target.codexExecutable else { throw MCPClientSetupError.missingCodex }
                return try MCPCodexConfiguration.isInstalled(in: file.original, executable: executable, command: command)
            }
            return try MCPClientConfiguration.addingJSON(to: file.original, kind: target.kind, command: command) == nil
        } catch let error as MCPClientSetupError {
            throw error
        } catch {
            throw MCPClientSetupError.invalidConfiguration
        }
    }

    func install(_ target: MCPClientTarget, command: String) throws -> Result {
        do {
            let file = try MCPConfigurationFile(url: target.configurationURL)
            let replacement: Data?
            if target.kind == .codex {
                guard let executable = target.codexExecutable else { throw MCPClientSetupError.missingCodex }
                replacement = try MCPCodexConfiguration.adding(to: file.original, executable: executable, command: command)
            } else {
                replacement = try MCPClientConfiguration.addingJSON(to: file.original, kind: target.kind, command: command)
            }
            guard let replacement else { return Result(alreadyPresent: true, backupURL: nil) }
            try Task.checkCancellation()
            return Result(alreadyPresent: false, backupURL: try file.commit(replacement))
        } catch let error as MCPClientSetupError {
            throw error
        } catch {
            throw MCPClientSetupError.fileAccess
        }
    }
}
