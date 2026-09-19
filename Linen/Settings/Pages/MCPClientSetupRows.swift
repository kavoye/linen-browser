// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MCPClientSetupRows: View {
    @State private var targets: [MCPClientTarget] = []
    @State private var installer = MCPClientInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(targets) { target in
                if target.id != targets.first?.id {
                    RowSeparator()
                }
                MCPClientSetupRow(target: target, installer: installer)
            }
        }
        .task { targets = MCPClientDiscovery.targets() }
    }
}

private struct MCPClientSetupRow: View {
    let target: MCPClientTarget
    let installer: MCPClientInstaller
    @State private var selectedURL: URL?
    @State private var message: String?
    @State private var backupURL: URL?
    @State private var isAdding = false
    @State private var isAdded = false
    @State private var isChecking = true
    @State private var refreshID = UUID()

    var body: some View {
        DetailRow(verbatimTitle: target.kind.name, verbatimCaption: caption) {
            HStack(spacing: 8) {
                SettingsButton(title: isAdded ? "Added" : "Add", symbol: isAdded ? "checkmark" : "plus") {
                    add()
                }
                .disabled(isChecking || isAdding || isAdded || (!target.isDetected && selectedURL == nil))
                .accessibilityLabel(Text("Add Linen to \(target.kind.name)"))

                SettingsMoreMenu {
                    Button("Choose Configuration…") { chooseConfiguration() }
                    Button("Show Configuration") {
                        NSWorkspace.shared.activateFileViewerSelecting([configurationURL])
                    }
                    if let backupURL {
                        Button("Show Backup") { NSWorkspace.shared.activateFileViewerSelecting([backupURL]) }
                    }
                }
                .accessibilityLabel(Text("Setup Options for \(target.kind.name)"))
                .disabled(isAdding)
            }
        }
        .task(id: configurationURL) { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
    }

    private var configurationURL: URL {
        selectedURL ?? target.configurationURL
    }

    private var caption: String? {
        if isAdding {
            return String(localized: "Adding Linen…")
        } else if let message {
            return message
        } else if !isAdded && !target.isDetected && selectedURL == nil {
            return String(localized: "Not detected. Install the client or choose its configuration file.")
        }
        return nil
    }

    private func add() {
        refreshID = UUID()
        var destination = target
        destination.configurationURL = configurationURL
        isAdding = true
        message = nil
        Task {
            defer { isAdding = false }
            do {
                let result = try await installer.install(destination, command: MCPClientConfiguration.command)
                backupURL = result.backupURL
                isAdded = true
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func refreshStatus() async {
        guard !isAdding else { return }
        let id = UUID()
        refreshID = id
        isChecking = true
        var destination = target
        destination.configurationURL = configurationURL
        defer {
            if refreshID == id {
                isChecking = false
            }
        }
        do {
            let installed = try await installer.isInstalled(destination, command: MCPClientConfiguration.command)
            guard !Task.isCancelled, refreshID == id, !isAdding else { return }
            isAdded = installed
            message = nil
        } catch {
            guard !Task.isCancelled, refreshID == id, !isAdding else { return }
            isAdded = false
            message = error.localizedDescription
        }
    }

    private func chooseConfiguration() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Configuration")
        panel.prompt = String(localized: "Choose")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = configurationURL.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            selectedURL = url
            isAdded = false
            message = nil
            backupURL = nil
        }
    }
}
