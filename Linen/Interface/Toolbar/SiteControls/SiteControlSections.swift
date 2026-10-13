// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

private struct SiteZoomSection: View {
    let tab: BrowserTab

    private var percentage: String {
        "\(Int((tab.zoomLevel * 100).rounded()))%"
    }

    var body: some View {
        SiteControlRow(symbol: "textformat.size", title: "Page Zoom") {
            HStack(spacing: 0) {
                zoomButton("minus", help: "Zoom Out") {
                    tab.zoomOut()
                }

                Divider()
                    .frame(height: 12)

                Button {
                    tab.resetZoom()
                } label: {
                    Text(verbatim: percentage)
                        .font(Theme.Font.label)
                        .monospacedDigit()
                        .frame(width: 40, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset Zoom")

                Divider()
                    .frame(height: 12)

                zoomButton("plus", help: "Zoom In") {
                    tab.zoomIn()
                }
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func zoomButton(
        _ symbol: String,
        help: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SiteHandlingSection: View {
    let browser: BrowserModel
    let tab: BrowserTab

    private var siteOrigin: String {
        browser.siteOrigin(for: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            SiteZoomSection(tab: tab)

            if !tab.assistantAccess.origin.isEmpty {
                SiteControlRow(symbol: "sparkles", title: "Assistant Access") {
                    AssistantAccessMenu(tab: tab)
                }
            }

            if tab.context.settings.sleepsInactiveTabs, !siteOrigin.isEmpty {
                SiteControlRow(symbol: "bolt", title: "Keep Website Loaded") {
                    SiteControlToggle(
                        isOn: browser.keepsActive(tab),
                        set: { browser.setKeepsActive($0, for: tab) }
                    )
                }
            }
        }
    }
}

struct SiteMediaSection: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        SiteControlGroup {
            SiteControlRow(symbol: "play.rectangle", title: "Autoplay") {
                SitePolicyMenu(
                    options: AutoplayPolicy.allCases.map { ($0, String(localized: $0.label)) },
                    selection: browser.autoplay(for: tab)
                ) {
                    browser.setAutoplay($0, for: tab)
                }
            }

            SiteControlRow(symbol: "macwindow.on.rectangle", title: "Pop-up Windows") {
                SitePolicyMenu(
                    options: PopupPolicy.allCases.map { ($0, String(localized: $0.label)) },
                    selection: browser.popups(for: tab)
                ) {
                    browser.setPopups($0, for: tab)
                }
            }

            if tab.context.settings.automaticPictureInPicture {
                SiteControlRow(symbol: "pip", title: "Auto Picture in Picture") {
                    SiteControlToggle(
                        isOn: browser.allowsAutomaticPicture(tab),
                        set: { browser.setAllowsAutomaticPicture($0, for: tab) }
                    )
                }
            }
        }
    }
}

struct SiteSafetySection: View {
    let tab: BrowserTab
    let blockableHost: String?

    private var visiblePermissions: [WebPermission] {
        WebPermission.allCases.filter { permission in
            tab.permissions.live.contains(permission)
                || tab.permissions.sessionGrants.contains(permission)
                || tab.permissions.menuPolicy(for: permission) == .allow
        }
    }

    var body: some View {
        SiteControlGroup {
            if let blockableHost {
                SiteControlRow(symbol: "shield", title: "Block Trackers") {
                    HStack(spacing: 7) {
                        TrackerInfoButton(tab: tab, host: blockableHost)

                        SiteControlToggle(
                            isOn: !tab.context.contentBlocker.isExempt(blockableHost),
                            set: { blocks in
                                tab.context.contentBlocker.setExempt(!blocks, for: blockableHost)
                                tab.webView.reload()
                            }
                        )
                    }
                }
            }

            if !tab.permissions.origin.isEmpty {
                ForEach(visiblePermissions, id: \.self) { permission in
                    SiteControlRow(symbol: permission.symbol, title: permission.label) {
                        PermissionPolicyMenu(tab: tab, permission: permission)
                    }
                }

                SitePermissionsMenu(tab: tab)
            }
        }
    }
}

private struct SitePermissionsMenu: View {
    let tab: BrowserTab

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            SiteControlRow(symbol: "hand.raised", title: "Permissions…") {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .background {
                if isHovering || isPresented {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 6,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 6
                    )
                    .fill(.quaternary)
                    .padding(.horizontal, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            SitePermissionsPanel(tab: tab)
                .chromePopoverAppearance()
        }
    }
}

private struct SitePermissionsPanel: View {
    let tab: BrowserTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, SiteControlsMetrics.inset)
                .padding(.vertical, 10)

            ForEach(WebPermission.allCases, id: \.self) { permission in
                SiteControlRow(symbol: permission.symbol, title: permission.label) {
                    PermissionPolicyMenu(tab: tab, permission: permission)
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 280)
    }
}

private struct AssistantAccessMenu: View {
    let tab: BrowserTab

    var body: some View {
        Menu {
            ForEach(AssistantAccessPolicy.allCases, id: \.self) { policy in
                Button {
                    tab.assistantAccess.set(policy)
                } label: {
                    if tab.assistantAccess.effectivePolicy == policy {
                        Label {
                            Text(policy.label)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(policy.label)
                    }
                }
            }
        } label: {
            Text(tab.assistantAccess.effectivePolicy.label)
                .font(Theme.Font.label)
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .fixedSize()
    }
}

private struct PermissionPolicyMenu: View {
    let tab: BrowserTab
    let permission: WebPermission

    private var center: TabPermissionCenter {
        tab.permissions
    }

    var body: some View {
        Menu {
            PermissionPolicyOptions(tab: tab, permission: permission)
        } label: {
            Text(center.menuPolicy(for: permission).label)
                .font(Theme.Font.label)
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .fixedSize()
    }
}

private struct PermissionPolicyOptions: View {
    let tab: BrowserTab
    let permission: WebPermission

    private var center: TabPermissionCenter {
        tab.permissions
    }

    var body: some View {
        ForEach([PermissionPolicy.ask, .allow, .deny], id: \.self) { policy in
            Button {
                center.set(policy, for: permission)
            } label: {
                if center.menuPolicy(for: permission) == policy {
                    Label {
                        Text(policy.label)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text(policy.label)
                }
            }
            .disabled(!center.isSecure && policy == .allow)
        }
    }
}

private struct SitePolicyMenu<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selection: Value
    let choose: (Value) -> Void

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    choose(option.value)
                } label: {
                    if option.value == selection {
                        Label {
                            Text(verbatim: option.label)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: option.label)
                    }
                }
            }
        } label: {
            Text(verbatim: selectedLabel)
                .font(Theme.Font.label)
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .controlSize(.small)
        .fixedSize()
    }
}
