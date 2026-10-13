// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

if CommandLine.arguments.contains("--mcp") {
    let socketOption = CommandLine.arguments.firstIndex(of: "--mcp-socket")
    let socketPath = socketOption.flatMap { index in
        CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
    }
    LocalMCPEndpoint.runStdioRelay(socketPath: socketPath ?? LocalMCPEndpoint.path)
}

UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
