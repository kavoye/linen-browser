// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MCPSettingsPage: View {
    let server: BrowserMCPServer
    let onBack: () -> Void

    var body: some View {
        SubPageHeader(backTitle: "Assistant", onBack: onBack)
        SettingsPageHeader(title: "External connections")

        SettingsCard {
            DetailRow(
                title: "MCP server",
                caption: "Let apps such as Claude Code use the assistant’s tools. Linen asks you once for each connection. Websites follow your Assistant Access settings."
            ) {
                SettingsToggle(Binding(get: { server.isEnabled }, set: { server.setEnabled($0) }))
                    .disabled(server.isPaused)
            }

            if let status = server.status {
                RowSeparator()
                DetailRow(verbatimTitle: status) { EmptyView() }
            }
        }

        SettingsSection(title: "Clients", symbol: "app.connected.to.app.below.fill", accessory: {
            CopyConfigurationButton(configuration: server.configuration)
        }) {
            MCPClientSetupRows()
        }

        if !server.sessions.isEmpty {
            SettingsSection(title: "Connected clients", symbol: "cable.connector") {
                ForEach(server.sessions) { session in
                    if session.id != server.sessions.first?.id {
                        RowSeparator()
                    }
                    MCPConnectionRow(session: session) { server.disconnect(session.id) }
                }
            }
        }
    }
}

private struct CopyConfigurationButton: View {
    let configuration: String

    @State private var showing = false

    var body: some View {
        SettingsButton(title: "Copy configuration") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(configuration, forType: .string)
            showing = true
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Copied to the clipboard")
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(verbatim: configuration)
                        .font(Theme.Font.monoCaption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(width: 420, height: 260)
        }
    }
}

private struct MCPConnectionRow: View {
    let session: MCPBrowserSession
    let disconnect: () -> Void

    var body: some View {
        DetailRow(
            verbatimTitle: session.displayName,
            verbatimCaption: caption
        ) {
            SettingsButton(title: "Disconnect", action: disconnect)
        }
    }

    private var caption: String {
        let count = String(localized: "Tool calls: \(session.completedCalls)")
        guard let action = session.lastActionTitle else { return count }
        return count + "\n" + String(localized: "Latest action: \(action)")
    }
}
