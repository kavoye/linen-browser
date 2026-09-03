// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantGrantsPage: View {
    let onBack: () -> Void

    private var policy: AgentActionPolicy {
        .shared
    }

    @State private var confirmingRevokeAll = false
    @State private var revokingHost: String?

    @MainActor
    static var summary: LocalizedStringResource {
        let count = AgentActionPolicy.shared.grantsByHost.count
        return count == 0 ? "None" : "\(count) websites"
    }

    var body: some View {
        SubPageHeader(backTitle: "Assistant", onBack: onBack)

        SettingsPageHeader(
            title: "Allowed without asking",
            caption: "Websites the assistant may act on without asking."
        )

        SettingsCard {
            if policy.grants.isEmpty {
                SettingsEmptyState(
                    symbol: "hand.raised",
                    title: "Nothing always-allowed",
                    caption: "Websites appear here after you choose “Always Allow”."
                )
            } else {
                ForEach(Array(policy.grantsByHost.enumerated()), id: \.element.host) { index, entry in
                    if index > 0 {
                        RowSeparator()
                    }

                    SiteRow(
                        host: entry.host,
                        summary: entry.categories
                            .map { String(localized: $0.listName) }
                            .formatted(.list(type: .and, width: .narrow))
                    ) {
                        SettingsButton(title: "Revoke…", isDestructive: true) {
                            revokingHost = entry.host
                        }
                    }
                }
            }
        }
        .padding(.top, 6)

        if !policy.grants.isEmpty {
            SectionActions {
                SettingsButton(title: "Revoke All", isDestructive: true, symbol: "hand.raised.slash") {
                    confirmingRevokeAll = true
                }
            }
            .confirmationDialog(
                "Revoke every saved permission?",
                isPresented: $confirmingRevokeAll
            ) {
                Button("Revoke All", role: .destructive) { policy.revokeAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The assistant will ask again before acting on these websites.")
            }
            .confirmationDialog(
                revokingHost.map {
                    Text("Revoke the permissions for “\($0)”?")
                } ?? Text(verbatim: ""),
                isPresented: Binding(get: { revokingHost != nil }, set: { if !$0 { revokingHost = nil } })
            ) {
                Button("Revoke", role: .destructive) {
                    guard let host = revokingHost else { return }
                    for grant in policy.grants where grant.host == host {
                        policy.revoke(grant)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The assistant will ask again before acting on this website.")
            }
        }
    }
}
