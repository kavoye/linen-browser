// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct WebsiteSettings: View {
    @Bindable var settings: BrowserSettings

    let permissions: SitePermissions

    init(settings: BrowserSettings, permissions: SitePermissions = .shared) {
        self.settings = settings
        self.permissions = permissions
    }

    @State private var destination: Destination?

    private enum Destination: Equatable {
        case permission(WebPermission)
        case site(String)
    }

    private var blocker: ContentBlocker {
        .shared
    }

    private var grants: AgentActionPolicy {
        .shared
    }

    private var entries: [SiteSettingsEntry] {
        SiteSettingsIndex.entries(
            permissions: permissions,
            grantsByHost: grants.grantsByHost,
            exemptHosts: blocker.exemptHosts
        )
    }

    var body: some View {
        switch destination {
        case .permission(let permission):
            PermissionDetailPage(permission: permission, permissions: permissions) {
                destination = nil
            }
        case .site(let origin):
            SiteDetailPage(
                origin: origin,
                permissions: permissions,
                onBack: { destination = nil }
            )
        case nil:
            overview
        }
    }

    @ViewBuilder
    private var overview: some View {
        SettingsPageHeader(
            title: "Websites",
            caption: "Defaults for every website, and the ones you’ve changed."
        )

        SettingsCard {
            DetailRow(title: "JavaScript") {
                SettingsToggle($settings.javaScriptEnabled)
            }
            .settingsAnchor("websites.javascript")

            RowSeparator()

            DetailRow(
                title: "Block pop-ups",
                caption: "Links you click still open."
            ) {
                SettingsToggle($settings.blocksPopups)
            }
            .settingsAnchor("websites.popups")

            RowSeparator()

            DetailRow(title: "Block known trackers") {
                SettingsToggle($settings.blocksTrackers)
            }
            .settingsAnchor("websites.trackers")
        }

        SettingsSection(title: "Autoplay", symbol: "play.rectangle") {
            OptionList(
                options: AutoplayPolicy.allCases.map {
                    .init(value: $0, label: $0.label, caption: $0.caption)
                },
                selection: settings.autoplay,
                onSelect: { settings.autoplay = $0 }
            )
        }
        .settingsAnchor("websites.autoplay")

        SettingsSection(title: "Permissions", symbol: "hand.raised") {
            ForEach(Array(WebPermission.allCases.enumerated()), id: \.element) { index, permission in
                if index > 0 {
                    RowSeparator()
                }
                DrillInRow(
                    title: permission.label,
                    symbol: permission.symbol,
                    tint: tint(for: permission),
                    detail: siteCount(for: permission)
                ) {
                    destination = .permission(permission)
                }
            }
        }
        .settingsAnchor("websites.permissions")

        SettingsSection(title: "Websites you’ve changed", symbol: "list.bullet") {
            if entries.isEmpty {
                SettingsEmptyState(
                    symbol: "globe",
                    title: "No websites changed",
                    caption: "Choose Site Settings in the toolbar to change one."
                )
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        RowSeparator()
                    }
                    WebsiteSettingsEntryRow(host: entry.host, summary: entry.summary) {
                        destination = .site(entry.origin)
                    }
                }
            }
        }
        .settingsAnchor("websites.list")
    }

    private func tint(for permission: WebPermission) -> Color {
        switch permission {
        case .location:
            Color(nsColor: .systemBlue)
        case .camera:
            Color(nsColor: .systemPink)
        case .microphone:
            Color(nsColor: .systemTeal)
        case .notifications:
            Color(nsColor: .systemOrange)
        }
    }

    private func siteCount(for permission: WebPermission) -> LocalizedStringResource {
        let count = permissions.origins(for: permission).count
        return count == 0 ? "None" : "\(count) websites"
    }
}

private struct WebsiteSettingsEntryRow: View {
    let host: String
    let summary: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            SiteRow(host: host, summary: summary) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .settingsRowHover(isActive: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

private struct PermissionDetailPage: View {
    let permission: WebPermission
    let permissions: SitePermissions
    let onBack: () -> Void

    @State private var confirmingRemoveAll = false

    private var origins: [String] {
        permissions.origins(for: permission)
    }

    var body: some View {
        SubPageHeader(backTitle: "Websites", onBack: onBack)

        SettingsPageHeader(title: permission.label)

        SettingsSection(title: "Other websites", symbol: permission.symbol) {
            OptionList(
                options: [
                    .init(value: PermissionPolicy.ask, label: PermissionPolicy.ask.label,
                          caption: "Every website asks the first time."),
                    .init(value: PermissionPolicy.deny, label: PermissionPolicy.deny.label,
                          caption: "No website may ask."),
                ],
                selection: permissions.defaultPolicy(for: permission),
                onSelect: { permissions.setDefault($0, for: permission) }
            )
        }

        SettingsSection(title: "Websites you’ve answered", symbol: "list.bullet") {
            if origins.isEmpty {
                SettingsEmptyState(
                    symbol: permission.slashedSymbol,
                    title: "No websites yet",
                    caption: "Websites appear here after you answer their requests."
                )
            } else {
                ForEach(Array(origins.enumerated()), id: \.element) { index, origin in
                    if index > 0 {
                        RowSeparator()
                    }
                    SiteRow(host: SiteSettingsIndex.host(of: origin)) {
                        SettingsMenu(
                            options: [
                                .init(value: PermissionPolicy.ask, label: String(localized: PermissionPolicy.ask.label)),
                                .init(value: PermissionPolicy.allow, label: String(localized: PermissionPolicy.allow.label)),
                                .init(value: PermissionPolicy.deny, label: String(localized: PermissionPolicy.deny.label)),
                            ],
                            selection: Binding(
                                get: { permissions.policy(for: origin, permission) },
                                set: { permissions.set($0, for: origin, permission) }
                            )
                        )
                    }
                }
            }
        }

        if !origins.isEmpty {
            SectionActions {
                SettingsButton(title: "Remove All…", isDestructive: true) {
                    confirmingRemoveAll = true
                }
            }
            .confirmationDialog(
                Text("Remove the \(permission.sentenceName) setting for every website?"),
                isPresented: $confirmingRemoveAll
            ) {
                Button("Remove All", role: .destructive) {
                    permissions.removeAll(for: permission)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(origins.count) websites will be asked again the next time they ask.")
            }
        }
    }
}

private struct SiteDetailPage: View {
    let origin: String
    let permissions: SitePermissions
    let onBack: () -> Void

    @State private var confirmingReset = false

    private var blocker: ContentBlocker {
        .shared
    }

    private var grants: AgentActionPolicy {
        .shared
    }

    private var host: String {
        SiteSettingsIndex.host(of: origin)
    }

    private var entry: SiteSettingsEntry? {
        SiteSettingsIndex.entries(
            permissions: permissions,
            grantsByHost: grants.grantsByHost,
            exemptHosts: blocker.exemptHosts
        )
        .first { $0.origin == origin }
    }

    var body: some View {
        SubPageHeader(backTitle: "Websites", onBack: onBack)

        SettingsPageHeader(
            verbatimTitle: SitePermissions.displayName(for: origin),
            verbatimCaption: String(localized: "Everything you’ve changed for this website.")
        )

        SettingsCard {
            DetailRow(title: "Assistant access") {
                SettingsMenu(
                    options: AssistantAccessPolicy.allCases.map {
                        .init(value: $0, label: String(localized: $0.label))
                    },
                    selection: Binding(
                        get: { permissions.assistantAccess(for: origin) },
                        set: { permissions.setAssistantAccess($0, for: origin) }
                    )
                )
            }

            RowSeparator()

            DetailRow(
                title: "Keep loaded",
                caption: "The website stays in memory even when unused."
            ) {
                SettingsToggle(Binding(
                    get: { permissions.keepsActive(origin) },
                    set: { permissions.setKeepsActive($0, for: origin) }
                ))
            }

            RowSeparator()

            DetailRow(
                title: "Block known trackers",
                caption: "Turn this off if the website breaks."
            ) {
                SettingsToggle(Binding(
                    get: { !blocker.isExempt(host) },
                    set: { blocker.setExempt(!$0, for: host) }
                ))
            }
        }

        SettingsSection(title: "Permissions", symbol: "hand.raised") {
            ForEach(Array(WebPermission.allCases.enumerated()), id: \.element) { index, permission in
                if index > 0 {
                    RowSeparator()
                }
                DetailRow(title: permission.label) {
                    SettingsMenu(
                        options: [
                            .init(value: PermissionPolicy.ask, label: String(localized: PermissionPolicy.ask.label)),
                            .init(value: PermissionPolicy.allow, label: String(localized: PermissionPolicy.allow.label)),
                            .init(value: PermissionPolicy.deny, label: String(localized: PermissionPolicy.deny.label)),
                        ],
                        selection: Binding(
                            get: { permissions.policy(for: origin, permission) },
                            set: { permissions.set($0, for: origin, permission) }
                        )
                    )
                }
            }
        }

        if let entry, !entry.assistantGrants.isEmpty {
            let names = entry.assistantGrants
                .map { String(localized: $0.listName) }
                .formatted(.list(type: .and, width: .narrow))
            Footnote("The assistant may do these without asking: \(names). Change this in Assistant settings.")
        }

        SectionActions {
            SettingsButton(title: "Reset This Website…", isDestructive: true) {
                confirmingReset = true
            }
        }
        .confirmationDialog(
            Text("Reset the settings for “\(SitePermissions.displayName(for: origin))”?"),
            isPresented: $confirmingReset
        ) {
            Button("Reset Website", role: .destructive) {
                reset()
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The website asks again before using the camera, microphone, location, or notifications, and the assistant asks before reading it.")
        }
    }

    private func reset() {
        for permission in WebPermission.allCases {
            permissions.set(.ask, for: origin, permission)
        }
        permissions.setAssistantAccess(.ask, for: origin)
        permissions.setKeepsActive(false, for: origin)
        blocker.setExempt(false, for: host)
    }
}
