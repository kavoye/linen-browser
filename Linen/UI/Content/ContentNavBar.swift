// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentNavBar: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @Environment(\.windowControlsInset) private var windowControlsInset
    @Environment(\.colorScheme) private var scheme

    @State private var barWidth: CGFloat = 0
    @State private var trailingClusterWidth: CGFloat = 0

    private var sidebar: SidebarLayout {
        coordinator.sidebar
    }

    private static let addressBarMinWidth: CGFloat = 260

    private static let clusterGap: CGFloat = 8

    private static let barInset: CGFloat = 10

    private static let buttonSlot: CGFloat = 36

    private var leadingReach: CGFloat {
        let cluster = 3 * Self.buttonSlot - 6
        return toolbarLeadingPadding + Self.barInset + cluster + Self.clusterGap
    }

    private var trailingReach: CGFloat {
        guard trailingClusterWidth > 0 else { return leadingReach }
        return Self.barInset + trailingClusterWidth + Self.clusterGap
    }

    private var extensionBudget: CGFloat? {
        guard barWidth > 0 else { return nil }
        let sideRoom = (barWidth - Self.addressBarMinWidth) / 2
        return max(0, sideRoom - Self.barInset - Self.clusterGap - Self.buttonSlot)
    }

    private var toolbarLeadingPadding: CGFloat {
        SidebarMetrics.toolbarLeadingPadding(
            isVisible: sidebar.isVisible,
            style: sidebar.style,
            windowControlsInset: windowControlsInset,
            contentInset: Self.barInset
        )
    }

    private var barColor: NSColor {
        LoomChrome.sampledColor(
            ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
            scheme: scheme
        )
    }

    private var barIsLight: Bool {
        PageInk.isLight(
            LoomChrome.sampledColor(
                ChromeBand.measuredColor(browser: browser, coordinator: coordinator),
                scheme: scheme
            ),
            scheme: scheme
        )
    }

    var body: some View {
        barContent
        .environment(\.chromeIsLight, barIsLight)
        .environment(\.chromeWash, .of(barColor, isLight: barIsLight))
        .environment(\.windowColorScheme, scheme)
        .environment(\.colorScheme, barIsLight ? .light : .dark)
        .animation(nil, value: barIsLight)
    }

    private var barContent: some View {
        HStack(spacing: 6) {
            navigationControls

            Spacer(minLength: 8)

            addressSurface
                .frame(maxWidth: Theme.addressBarMaxWidth)
                .padding(.leading, max(0, trailingReach - leadingReach))
                .padding(.trailing, max(0, leadingReach - trailingReach))

            Spacer(minLength: 8)

            trailingControls
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingClusterWidth = $0 }
        }
        .padding(.horizontal, Self.barInset)
        .padding(.leading, toolbarLeadingPadding)
        .frame(height: Theme.topBarHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .background { WindowDragArea() }
        .onDrop(of: [.url, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if let tab = browser.activeTab {
                        tab.load(url)
                    } else {
                        coordinator.openNewTab(url: url)
                    }
                }
            }
            return true
        }
    }

    private var addressSurface: some View {
        AskSurface(placement: .toolbar, browser: browser, coordinator: coordinator)
            .holdsWindowStillOnHover()
    }

    private var reloadHelp: LocalizedStringResource {
        (browser.activeTab?.isLoading ?? false) ? "Stop" : "Reload"
    }

    private var navigationControls: some View {
        HStack(spacing: 6) {
            ToolbarButton(
                symbol: "chevron.left",
                enabled: browser.activeTab?.canGoBack ?? false,
                help: String(localized: "Back"),
                heldMenu: {
                    guard let tab = browser.activeTab else { return nil }
                    return NavigationHoldMenu.back(for: tab, coordinator: coordinator)
                }
            ) {
                browser.activeTab?.goBack()
            }
            ToolbarButton(
                symbol: "chevron.right",
                enabled: browser.activeTab?.canGoForward ?? false,
                help: String(localized: "Forward"),
                heldMenu: {
                    guard let tab = browser.activeTab else { return nil }
                    return NavigationHoldMenu.forward(for: tab, coordinator: coordinator)
                }
            ) {
                browser.activeTab?.goForward()
            }
            ToolbarButton(
                symbol: (browser.activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise",
                enabled: !(browser.activeTab?.urlString.isEmpty ?? true),
                help: String(localized: reloadHelp),
                heldMenu: {
                    guard let tab = browser.activeTab else { return nil }
                    return NavigationHoldMenu.reload(for: tab)
                }
            ) {
                guard let tab = browser.activeTab else { return }
                if tab.isLoading {
                    tab.webView.stopLoading()
                } else {
                    tab.webView.reload()
                }
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 6) {
            if !coordinator.isShowingSettings {
                StoreInstallButton(manager: coordinator.extensions, browser: browser)
            }
            ExtensionActionsCluster(
                manager: coordinator.extensions,
                browser: browser,
                availableWidth: extensionBudget
            )

            SidePanelToggle(coordinator: coordinator)
        }
    }
}

enum ChromeBand {
    static func measuredColor(browser: BrowserModel, coordinator: AppCoordinator) -> NSColor? {
        guard coordinator.settings.matchesWebsiteColor else { return nil }
        return pageColor(browser: browser, coordinator: coordinator)
    }

    static func pageColor(browser: BrowserModel, coordinator: AppCoordinator) -> NSColor? {
        guard !coordinator.isShowingSettings, !showsStartPage(browser: browser) else { return nil }
        guard browser.activeSplit == nil else { return nil }
        return browser.activeTab?.pageColor
    }

    static func showsStartPage(browser: BrowserModel) -> Bool {
        showsStartPage(for: browser.activeTab)
    }

    static func showsStartPage(for tab: BrowserTab?) -> Bool {
        guard let tab else { return BrowserSettings.shared.newTab != .blank }
        if tab.isShowingStartPage {
            return true
        }
        guard BrowserSettings.shared.newTab != .blank else { return false }
        return tab.hasNoPageYet && tab.internalPage == nil
    }
}

enum PageInk {
    static func isLight(_ color: NSColor?, scheme: ColorScheme) -> Bool {
        guard let rgb = color?.usingColorSpace(.sRGB), rgb.alphaComponent > 0.05 else {
            return scheme == .light
        }
        let ground = luminance(of: rgb) + 0.05
        let againstBlack = ground / 0.05
        let againstWhite = 1.05 / ground
        return againstBlack > againstWhite
    }

    static func luminance(of rgb: NSColor) -> CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }
}
