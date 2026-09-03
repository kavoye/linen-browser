// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

nonisolated enum SiteControlsMetrics {
    static let inset: CGFloat = 14
}

struct SiteControlsMenu: View {
    let browser: BrowserModel

    @State private var hovering = false
    @State private var isPresented = false
    @Environment(\.chromeIsLight) private var chromeIsLight
    @Environment(\.chromeIconExtent) private var extent
    @Environment(\.windowColorScheme) private var windowColorScheme

    private var tab: BrowserTab? {
        browser.activeTab
    }
    private var hasPage: Bool {
        guard let tab, !tab.urlString.isEmpty else { return false }
        return !tab.isShowingSystemPage
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering))
                .frame(width: extent, height: extent)
                .hoverBackground(isActive: hovering || isPresented)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasPage)
        .opacity(hasPage ? 1 : 0.4)
        .onHover { hovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if let tab {
                SiteControlsPanel(browser: browser, tab: tab)
                    .environment(\.colorScheme, windowColorScheme)
            }
        }
        .help("Website Settings")
    }
}

private struct SiteControlsPanel: View {
    let browser: BrowserModel
    let tab: BrowserTab

    private var siteOrigin: String {
        browser.siteOrigin(for: tab)
    }

    private var blockableHost: String? {
        guard BrowserSettings.shared.blocksTrackers,
              let host = URL(string: tab.urlString)?.host(),
              !host.isEmpty
        else { return nil }
        return host
    }

    private var showsSafety: Bool {
        blockableHost != nil || !tab.permissions.origin.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SiteControlsHeader(tab: tab)

            SiteHandlingSection(browser: browser, tab: tab)

            if !siteOrigin.isEmpty {
                SiteMediaSection(browser: browser, tab: tab)
            }

            if showsSafety {
                SiteSafetySection(tab: tab, blockableHost: blockableHost)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 340)
        .background(.ultraThickMaterial)
    }
}

private struct SiteControlGroup<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, SiteControlsMetrics.inset)
                .padding(.top, 16)
                .padding(.bottom, 4)

            content
        }
    }
}

private struct SiteControlsHeader: View {
    let tab: BrowserTab

    private var host: String {
        let permissionHost = tab.permissions.displayHost
        if !permissionHost.isEmpty {
            return permissionHost
        }
        return URL(string: tab.urlString)?.host() ?? tab.title
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                } else {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Website Settings")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    SiteCertificateButton(tab: tab)
                    Text(verbatim: host)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SiteControlsMetrics.inset)
        .padding(.vertical, 12)
    }
}

private struct SiteCertificateButton: View {
    let tab: BrowserTab

    @State private var hovering = false

    private var symbol: String? {
        tab.security.symbol
    }

    var body: some View {
        if let symbol {
            let opens = CertificatePanel.canShow(for: tab)
            Button {
                CertificatePanel.show(for: tab)
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tab.security.tint)
                    .opacity(hovering && opens ? 0.7 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!opens)
            .onHover { hovering = $0 }
            .help(opens ? Text("Show Certificate") : Text(verbatim: ""))
        }
    }
}

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

private struct SiteHandlingSection: View {
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

            if BrowserSettings.shared.sleepsInactiveTabs, !siteOrigin.isEmpty {
                SiteControlRow(symbol: "bolt", title: "Keep Website Loaded") {
                    SiteControlToggle(
                        isOn: browser.keepsActive(tab),
                        set: { browser.setKeepsActive($0, for: tab) }
                    )
                }
            }
        }
        .padding(.bottom, 6)
    }
}

private struct SiteMediaSection: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        SiteControlGroup(title: "Media and windows") {
            SiteControlRow(symbol: "play.rectangle", title: "Auto-Play") {
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

            if BrowserSettings.shared.automaticPictureInPicture {
                SiteControlRow(symbol: "pip", title: "Automatic Picture in Picture") {
                    SiteControlToggle(
                        isOn: browser.allowsAutomaticPicture(tab),
                        set: { browser.setAllowsAutomaticPicture($0, for: tab) }
                    )
                }
            }
        }
    }
}

private struct SiteSafetySection: View {
    let tab: BrowserTab
    let blockableHost: String?

    var body: some View {
        SiteControlGroup(title: "Trackers and permissions") {
            if let blockableHost {
                SiteControlRow(symbol: "shield", title: "Block Trackers") {
                    HStack(spacing: 7) {
                        TrackerInfoButton(tab: tab, host: blockableHost)

                        SiteControlToggle(
                            isOn: !ContentBlocker.shared.isExempt(blockableHost),
                            set: { blocks in
                                ContentBlocker.shared.setExempt(!blocks, for: blockableHost)
                                tab.webView.reload()
                            }
                        )
                    }
                }
            }

            if !tab.permissions.origin.isEmpty {
                ForEach(WebPermission.allCases, id: \.self) { permission in
                    SiteControlRow(symbol: permission.symbol, title: permission.label) {
                        PermissionPolicyMenu(tab: tab, permission: permission)
                    }
                }
            }
        }
    }
}

private struct SiteControlToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { set($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

private struct TrackerInfoButton: View {
    let tab: BrowserTab
    let host: String

    @State private var isPresented = false

    private var isBlocking: Bool {
        !ContentBlocker.shared.isExempt(host)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isPresented ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)
                )
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About Tracker Blocking")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            TrackerInfoPopover(tab: tab, isBlocking: isBlocking)
        }
    }
}

private struct TrackerInfoPopover: View {
    let tab: BrowserTab
    let isBlocking: Bool

    @State private var domains: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackerInfoHeader(isBlocking: isBlocking)

            Divider().padding(.horizontal, SiteControlsMetrics.inset)

            if let domains {
                TrackerDomainList(domains: domains, isBlocking: isBlocking)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking this page…")
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }

            Divider().padding(.horizontal, SiteControlsMetrics.inset)

            TrackerInfoCaption()
        }
        .frame(width: 310)
        .background(.ultraThickMaterial)
        .task(id: tab.urlString) {
            let result = await TrackerPageReport.matchingDomains(in: tab.webView)
            guard !Task.isCancelled else { return }
            domains = result
        }
    }
}

private struct TrackerInfoHeader: View {
    let isBlocking: Bool

    private var status: LocalizedStringResource {
        isBlocking ? "Enabled for this website" : "Disabled for this website"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isBlocking ? "shield.checkered" : "shield.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isBlocking ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)
                )
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tracker blocking")
                    .font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

private struct TrackerDomainList: View {
    let domains: [String]
    let isBlocking: Bool

    private var listHeight: CGFloat {
        min(CGFloat(domains.count) * 27, 160)
    }

    private var heading: LocalizedStringResource {
        isBlocking ? "Blocked on this page" : "Would be blocked on this page"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if domains.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("No trackers found")
                            .font(Theme.Font.rowTitle)
                        Text("This page does not reference known tracker domains.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            } else {
                HStack {
                    Text(heading)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(domains.count, format: .number)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(domains, id: \.self) { domain in
                            Label {
                                Text(verbatim: domain)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: "shield.slash")
                                    .foregroundStyle(.secondary)
                            }
                            .font(Theme.Font.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: listHeight)
            }
        }
        .padding(.horizontal, SiteControlsMetrics.inset)
        .padding(.vertical, 11)
    }
}

private struct TrackerInfoCaption: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Linen blocks third-party requests to known advertising, analytics, session-recording, social-pixel, and fingerprinting domains.")
            Text("The list shows the known tracker domains this page refers to. A request that is stopped before it loads can be missing.")
        }
        .font(Theme.Font.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
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
        .menuStyle(.button)
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
        } label: {
            Text(center.menuPolicy(for: permission).label)
                .font(Theme.Font.label)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
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
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }
}

private struct SiteControlRow<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringResource
    let accessory: Accessory

    init(
        symbol: String,
        title: LocalizedStringResource,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.symbol = symbol
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12.5))

            Spacer(minLength: 12)

            accessory
        }
        .padding(.horizontal, SiteControlsMetrics.inset)
        .frame(minHeight: 36)
    }
}

struct TabPictureBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        guard let tab = browser.activeTab, tab.hasVideo, !tab.isDeferred,
              tab.internalPage == nil
        else { return nil }
        return tab
    }

    private enum Face: Equatable {
        case video(out: Bool)
        case absent
    }

    private var face: Face {
        guard let tab else { return .absent }
        return .video(out: tab.isPictureOut)
    }

    private func pictureHelp(isOut: Bool) -> LocalizedStringResource {
        isOut ? "Exit Picture in Picture" : "Picture in Picture"
    }

    var body: some View {
        Group {
            if let tab {
                let isOut = tab.isPictureOut
                ChromeIcon(
                    symbol: isOut ? "pip.exit" : "pip.enter",
                    weight: .semibold,
                    help: String(localized: pictureHelp(isOut: isOut))
                ) {
                    coordinator.togglePictureInPicture(for: tab)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: face)
    }
}

struct PopupBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var blocked: (tab: BrowserTab, url: URL)? {
        guard let tab = browser.activeTab, let url = tab.popups.blocked else { return nil }
        return (tab, url)
    }

    var body: some View {
        Group {
            if let blocked {
                ChromeIcon(
                    symbol: "macwindow.badge.plus",
                    weight: .semibold,
                    tint: Theme.systemAccent,
                    help: String(localized: "Show Blocked Pop-up")
                ) {
                    blocked.tab.popups.clear()
                    coordinator.openNewTab(url: blocked.url)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: blocked?.url)
    }
}

struct TabAudioBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        guard let tab = browser.activeTab, tab.isPlayingAudio || tab.isMuted else { return nil }
        return tab
    }

    private enum Face: Equatable {
        case speaking
        case tab(muted: Bool)
        case absent
    }

    private var face: Face {
        if coordinator.isAgentSpeaking {
            return .speaking
        }
        guard let tab else { return .absent }
        return .tab(muted: tab.isMuted)
    }

    private func muteHelp(isMuted: Bool) -> LocalizedStringResource {
        isMuted ? "Unmute This Tab" : "Mute This Tab"
    }

    var body: some View {
        Group {
            if coordinator.isAgentSpeaking {
                ChromeIcon(
                    symbol: "speaker.wave.2.fill",
                    weight: .semibold,
                    tint: Theme.systemAccent,
                    help: String(localized: "Stop Speaking")
                ) {
                    coordinator.stopAgentSpeech()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else if let tab {
                ChromeIcon(
                    symbol: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    weight: .semibold,
                    isSubdued: tab.isMuted,
                    tint: tab.isMuted ? nil : Theme.systemAccent,
                    help: String(localized: muteHelp(isMuted: tab.isMuted))
                ) {
                    coordinator.toggleMute(tab: tab)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: face)
    }
}
