// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MCPSettingsPage: View {
    let server: BrowserMCPServer
    let onBack: () -> Void

    var body: some View {
        SubPageHeader(backTitle: "Advanced", onBack: onBack)
        SettingsPageHeader(title: "External Connections")

        SettingsCard {
            DetailRow(
                title: "MCP server",
                caption: "Connect external assistants to tabs you choose. Private tabs are never shared."
            ) {
                SettingsToggle(Binding(get: { server.isEnabled }, set: { server.setEnabled($0) }))
                    .disabled(server.isPaused)
            }
            .settingsAnchor("advanced.mcp")

            if let status = server.status {
                RowSeparator()
                DetailRow(verbatimTitle: status) { EmptyView() }
            }
        }

        SettingsSection(title: "Clients", symbol: "app.connected.to.app.below.fill", accessory: {
            SettingsButton(title: "Copy Configuration") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(server.configuration, forType: .string)
            }
        }) {
            MCPClientSetupRows()
        }

        if !server.sessions.isEmpty {
            SettingsSection(title: "Connected Clients", symbol: "cable.connector") {
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

private struct MCPConnectionRow: View {
    let session: MCPBrowserSession
    let disconnect: () -> Void

    var body: some View {
        DetailRow(
            verbatimTitle: session.clientName,
            verbatimCaption: caption
        ) {
            SettingsButton(title: "Disconnect", action: disconnect)
        }
    }

    private var caption: String {
        let count = String(localized: "Shared tabs: \(session.grants.count) · Tool calls: \(session.completedCalls)")
        guard let action = session.lastActionTitle else { return count }
        return count + "\n" + String(localized: "Latest action: \(action)")
    }
}
