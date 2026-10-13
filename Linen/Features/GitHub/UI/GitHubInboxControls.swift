// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GitHubInboxHeader<Picker: View>: View {
    let model: GitHubPanelModel
    let onProfile: (URL) -> Void
    let onManage: () -> Void
    let onPrivateAccess: () -> Void
    @ViewBuilder let picker: Picker

    private static var iconExtent: CGFloat {
        22
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 2) {
            GitHubAccountButton(account: model.account, onOpen: onProfile)
            picker
            Spacer(minLength: 0)
            if model.isRefreshing {
                Spinner(size: 11).foregroundStyle(.secondary).frame(width: Self.iconExtent, height: Self.iconExtent)
            } else {
                ChromeIcon(symbol: "arrow.clockwise", weight: .semibold,
                           isEnabled: !model.isRateLimited, isSubdued: true,
                           extent: Self.iconExtent, help: String(localized: "Refresh GitHub"),
                           glyphOffset: CGSize(width: 0, height: -1), action: model.refresh)
            }
            GitHubMoreMenu(extent: Self.iconExtent, help: "GitHub account options") {
                if let account = model.account {
                    Text("Signed in as \(account.login)")
                    Divider()
                }
                Toggle("Notify About My Pull Requests", isOn: $model.notifiesAboutPullRequests)
                Divider()
                Button("Manage GitHub Access", action: onManage)
                Button("Include Private Repositories…", action: onPrivateAccess)
                Divider()
                Button("Disconnect GitHub", role: .destructive, action: model.disconnect)
            }
        }
        .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
    }
}

private struct GitHubAccountButton: View {
    let account: GitHubAccount?
    let onOpen: (URL) -> Void

    var body: some View {
        Button {
            if let url = account?.profileURL {
                onOpen(url)
            }
        } label: {
            HStack(spacing: 7) {
                GitHubAvatar(url: account?.avatarURL, login: account?.login ?? "", size: 20)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(account?.profileURL == nil)
        .help("Open GitHub profile")
        .accessibilityLabel(Text(verbatim: account?.displayName ?? String(localized: "GitHub")))
        .accessibilityHint("Opens your GitHub profile")
    }
}

struct GitHubAvatar: View {
    let url: URL?
    let login: String
    let size: CGFloat

    var body: some View {
        GitHubCachedImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Circle().fill(Theme.Wash.selection)
                Text(verbatim: String(login.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
        .help(login)
    }
}

struct GitHubMoreMenu<Content: View>: View {
    let extent: CGFloat
    let help: LocalizedStringResource
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering, subdued: true))
                .hoverLift(hovering)
                .frame(width: extent, height: extent)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

struct GitHubInboxFooter: View {
    let model: GitHubPanelModel
    let onManage: () -> Void
    let onPrivateAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(Theme.warning).textSelection(.enabled)
            }
            HStack(spacing: 5) {
                Circle().fill(model.errorMessage == nil ? Theme.success : Theme.warning).frame(width: 4, height: 4)
                if let updated = model.lastUpdated {
                    Text("Updated \(updated, format: .dateTime.hour().minute())")
                } else {
                    Text(model.isRefreshing ? "Connecting…" : "Waiting for update")
                }
                Spacer(minLength: 0)
                accessIcon
            }
            .foregroundStyle(.secondary)
        }
        .font(Theme.Font.caption)
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Wash.faint)
    }

    @ViewBuilder
    private var accessIcon: some View {
        if model.requiresSSO {
            ChromeIcon(symbol: "exclamationmark.shield", size: 10, tint: Theme.warning, extent: 18,
                       help: String(localized: "Some organizations require authorization."), action: onManage)
        } else if let hasPrivateAccess = model.hasPrivateAccess {
            if hasPrivateAccess {
                ChromeIcon(symbol: "lock", size: 10, isSubdued: true, extent: 18,
                           help: String(localized: "Can read public and private repositories."), action: onManage)
            } else {
                ChromeIcon(symbol: "globe", size: 10, isSubdued: true, extent: 18,
                           help: String(localized: "Can read public repositories only."), action: onPrivateAccess)
            }
        }
    }
}
