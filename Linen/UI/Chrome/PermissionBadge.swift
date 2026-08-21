// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct PermissionBadge: View {
    let browser: BrowserModel

    var body: some View {
        if let tab = browser.activeTab {
            TabPermissionBadge(tab: tab)
                .id(tab.id)
        }
    }
}

private struct TabPermissionBadge: View {
    let tab: BrowserTab

    private var center: TabPermissionCenter {
        tab.permissions
    }

    static var windowScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }

    var body: some View {
        let face = center.badge
        Group {
            switch face {
            case .hidden:
                EmptyView()
            case .asking(let permission):
                icon(permission.symbol, tint: Theme.accent, help: askingHelp(for: permission))
                    .symbolEffect(.pulse)
            case .live(let permission):
                icon(permission.symbol, tint: permission.liveTint, help: liveHelp(for: permission))
            case .granted(let permission):
                icon(permission.symbol, help: "Permissions for this website")
            case .denied(let permission):
                icon(permission.slashedSymbol, subdued: true, help: "Permissions for this website")
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: face)
        .popover(
            isPresented: Binding(
                get: { center.isPopoverPresented },
                set: { center.isPopoverPresented = $0 }
            ),
            arrowEdge: .bottom
        ) {
            PermissionPopover(tab: tab)
                .environment(\.colorScheme, Self.windowScheme)
        }
        .onDisappear {
            center.isPopoverPresented = false
        }
    }

    private func askingHelp(for permission: WebPermission) -> LocalizedStringResource {
        "\(String(localized: permission.label)) — answering"
    }

    private func liveHelp(for permission: WebPermission) -> LocalizedStringResource {
        "\(String(localized: permission.label)) in use"
    }

    private func icon(
        _ symbol: String,
        tint: Color? = nil,
        subdued: Bool = false,
        help: LocalizedStringResource
    ) -> some View {
        ChromeIcon(
            symbol: symbol,
            weight: .semibold,
            isSubdued: subdued,
            tint: tint,
            help: String(localized: help)
        ) {
            center.isPopoverPresented.toggle()
        }
    }
}

// MARK: - The popover

private struct PermissionPopover: View {
    let tab: BrowserTab

    private var center: TabPermissionCenter {
        tab.permissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let ask = center.currentAsk {
                askFace(ask)
            } else {
                recordFace
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, center.currentAsk == nil ? 7 : 14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tight))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            Group {
                if center.displayHost.isEmpty {
                    Text("This page")
                } else {
                    Text(verbatim: center.displayHost)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.bottom, 10)
    }

    // MARK: Ask

    private func question(for permission: WebPermission) -> LocalizedStringResource {
        switch permission {
        case .location:
            "Use your current location?"
        case .camera:
            "Use your camera?"
        case .microphone:
            "Use your microphone?"
        case .notifications:
            "Send you notifications?"
        }
    }

    private func askFace(_ ask: TabPermissionCenter.Ask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(question(for: ask.permission))
            } icon: {
                Image(systemName: ask.permission.symbol)
            }
            .font(.system(size: 13))

            Text("“Allow Once” lasts until you leave this website.")
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Don’t Allow") { center.answer(.deny) }
                Button("Allow Once") { center.answer(.once) }
                Button("Always Allow") { center.answer(.always) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    // MARK: Record

    private func caption(for state: TabPermissionCenter.RowState) -> LocalizedStringResource {
        switch state {
        case .live(always: true):
            "In use, always allowed"
        case .live(always: false):
            "In use, allowed until you leave"
        case .always:
            "Always allowed"
        case .session:
            "Allowed until you leave"
        case .denied:
            "Denied"
        case .asks:
            "Asks each time"
        }
    }

    private func captionColor(for row: TabPermissionCenter.Row) -> Color {
        if case .live = row.state {
            return row.permission.liveTint
        }
        return .secondary
    }

    private func chosen(_ policy: PermissionPolicy, for permission: WebPermission) -> Binding<Bool> {
        Binding {
            center.menuPolicy(for: permission) == policy
        } set: { isOn in
            guard isOn else { return }
            center.set(policy, for: permission)
        }
    }

    private var recordFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(center.rows) { row in
                if row.id != center.rows.first?.id {
                    Divider()
                }
                HStack(spacing: 10) {
                    Image(systemName: row.state == .denied ? row.permission.slashedSymbol : row.permission.symbol)
                        .font(Theme.Font.body)
                        .foregroundStyle(row.state == .denied ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.permission.label)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(caption(for: row.state))
                            .font(Theme.Font.caption)
                            .foregroundStyle(captionColor(for: row))
                    }

                    Spacer(minLength: 12)

                    Menu {
                        ForEach([PermissionPolicy.ask, .allow, .deny], id: \.self) { policy in
                            Toggle(isOn: chosen(policy, for: row.permission)) {
                                Text(policy.label)
                            }
                        }
                    } label: {
                        Text(center.menuPolicy(for: row.permission).label)
                            .font(Theme.Font.label)
                    }
                    .menuStyle(.button)
                    .controlSize(.small)
                    .fixedSize()
                }
                .padding(.vertical, 7)
            }
        }
    }
}
