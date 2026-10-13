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
    @Environment(\.chromeHoverLifts) private var hoverLifts

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
                .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering || isPresented))
                .hoverLift(hoverLifts && hovering && hasPage)
                .frame(width: extent, height: extent)
                .hoverBackground(isActive: !hoverLifts && (hovering || isPresented))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasPage)
        .opacity(hasPage ? 1 : 0.4)
        .onHover { hovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if let tab {
                SiteControlsPanel(browser: browser, tab: tab)
                    .chromePopoverAppearance()
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
        guard tab.context.settings.blocksTrackers,
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
    }
}

struct SiteControlGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, SiteControlsMetrics.inset)
                .padding(.vertical, 5)

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
                    FaviconImage(image: favicon)
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

struct SiteControlToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { set($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

struct SiteControlRow<Accessory: View>: View {
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
        .frame(minHeight: 32)
    }
}
