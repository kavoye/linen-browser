// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct IslandBar: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator
    let floating: FloatingGround
    let width: CGFloat
    let onTabButtonFrame: (CGRect) -> Void

    @State private var surface: AskSurfaceModel
    @State private var isMoreOpen = false

    init(
        browser: BrowserModel,
        coordinator: AppCoordinator,
        floating: FloatingGround,
        width: CGFloat,
        onTabButtonFrame: @escaping (CGRect) -> Void,
    ) {
        self.browser = browser
        self.coordinator = coordinator
        self.floating = floating
        self.width = width
        self.onTabButtonFrame = onTabButtonFrame
        _surface = State(initialValue: AskSurfaceModel(placement: .toolbar, browser: browser, coordinator: coordinator))
    }

    static let height: CGFloat = 40

    static func width(fullAddress: Bool, available: CGFloat) -> CGFloat {
        min(fullAddress ? 760 : 600, max(available, 0))
    }
    static let edgeGap: CGFloat = 14
    private static let extensionBudget: CGFloat = 3 * 36

    static func tabCountSymbol(_ count: Int) -> String {
        (1...50).contains(count) ? "\(count).square" : "square.on.square"
    }

    private var tab: BrowserTab? {
        browser.activeTab
    }

    private var status: AskSurfaceStatus? {
        if surface.isListening {
            return .listening
        }
        if coordinator.statusMessage != nil {
            return .warning
        }
        return surface.activity.isRunning ? .agent : nil
    }

    private var waveMotion: FluidWaves.Motion {
        let activity = surface.activity
        if activity.isThinking {
            return .thinking
        }
        return activity.isRunning || status == .listening ? .active : .calm
    }

    static func ground(for tab: BrowserTab?) -> NSColor? {
        guard let tab, !ChromeBand.showsStartPage(for: tab), tab.internalPage == nil else { return nil }
        return tab.canvasColor
    }

    private var onLight: Bool {
        floating.isLight
    }

    private var reloadHelp: LocalizedStringResource {
        (tab?.isLoading ?? false) ? "Stop" : "Reload"
    }

    private var divider: some View {
        Rectangle()
            .fill(floating.ink.opacity(0.14))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 2) {
            ToolbarButton(
                symbol: Self.tabCountSymbol(browser.tabs.count),
                enabled: true,
                isOn: coordinator.overlays.isTabListOpen,
                help: String(localized: "Show tabs"),
                heldMenu: { TabsHoldMenu.menu(browser: browser, coordinator: coordinator) }
            ) {
                coordinator.overlays.isTabListOpen.toggle()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MinimalShell.space)) } action: {
                onTabButtonFrame($0)
            }

            divider

            ToolbarButton(
                symbol: "chevron.left",
                enabled: tab?.canGoBack ?? false,
                help: String(localized: "Back"),
                heldMenu: {
                    guard let tab else { return nil }
                    return NavigationHoldMenu.back(for: tab, coordinator: coordinator)
                }
            ) {
                tab?.goBack()
            }
            ToolbarButton(
                symbol: "chevron.right",
                enabled: tab?.canGoForward ?? false,
                help: String(localized: "Forward"),
                heldMenu: {
                    guard let tab else { return nil }
                    return NavigationHoldMenu.forward(for: tab, coordinator: coordinator)
                }
            ) {
                tab?.goForward()
            }
            ToolbarButton(
                symbol: (tab?.isLoading ?? false) ? "xmark" : "arrow.clockwise",
                enabled: tab.map { $0.isLoading || $0.canReload } ?? false,
                help: String(localized: reloadHelp),
                heldMenu: {
                    guard let tab else { return nil }
                    return NavigationHoldMenu.reload(for: tab)
                }
            ) {
                guard let tab else { return }
                if tab.isLoading {
                    tab.stopLoading()
                } else {
                    tab.reload()
                }
            }

            if tab?.isPrivate == true {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChromeInk.glyph(onLight: onLight))
                    .frame(width: 24)
                    .help(String(localized: "Private Window"))
            }

            IslandAddress(
                tab: tab,
                resting: surface.restingContent,
                notice: coordinator.notice
            ) {
                coordinator.focusAddressBar()
            }
            .contextMenu { IslandAddressMenu(browser: browser, coordinator: coordinator) }

            Group {
                TabAudioBadge(browser: browser, coordinator: coordinator)
                    .frame(width: 30)
                TabPictureBadge(browser: browser, coordinator: coordinator)
                    .frame(width: 30)
                PermissionBadge(browser: browser)
                AutofillSaveBadge(browser: browser, coordinator: coordinator)
                PopupBadge(browser: browser, coordinator: coordinator)
                if let tab = browser.activeTab, tab.usesDeveloperMode {
                    DeveloperBadge(tab: tab, coordinator: coordinator)
                        .frame(width: 30)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                PinBadge(browser: browser)
                    .frame(width: 30)
                TranslationBadge(browser: browser, coordinator: coordinator)
                ReaderBadge(browser: browser)
                    .frame(width: 30)
                if browser.downloads.activeCount > 0 {
                    SidebarDownloadsButton(coordinator: coordinator)
                        .frame(width: 30)
                }
                SiteControlsMenu(browser: browser)
                    .frame(width: 30)
            }
            .environment(\.chromeIconExtent, 28)
            .environment(\.chromeHoverLifts, false)

            divider

            if !coordinator.isShowingSettings {
                StoreInstallButton(manager: coordinator.extensions, browser: browser)
            }
            ExtensionActionsCluster(
                manager: coordinator.extensions,
                browser: browser,
                availableWidth: Self.extensionBudget
            )

            ToolbarButton(
                symbol: "text.menu",
                enabled: true,
                isOn: isMoreOpen,
                help: String(localized: "More")
            ) {
                isMoreOpen.toggle()
            }
            .popover(isPresented: $isMoreOpen, arrowEdge: .bottom) {
                IslandMoreMenu(coordinator: coordinator, isPresented: $isMoreOpen)
            }

            UpdateBanner(updates: coordinator.updates)
                .environment(\.sidebarStyle, .icons)
                .frame(width: 30)
                .environment(\.chromeIconExtent, 28)
                .environment(\.chromeHoverLifts, false)

            SidePanelToggle(coordinator: coordinator)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: Self.height)
        .background {
            ZStack {
                FloatingChromeFill(shape: shape, ground: floating)
                if let status {
                    FluidWaves(color: status.color, motion: waveMotion)
                        .opacity(surface.activity.isThinking ? 0.42 : 0.36)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
                WindowDragArea()
                    .clipShape(shape)
            }
        }
        .overlay { shape.strokeBorder((onLight ? Color.black : .white).opacity(0.1), lineWidth: 0.5) }
        .shieldsPage(.island, coordinator: coordinator)
        .shadow(color: .black.opacity(onLight ? 0.12 : 0.3), radius: 10, y: 3)
        .environment(\.chromeIsLight, onLight)
        .environment(\.chromeWash, .of(floating.color, isLight: onLight))
        .environment(\.colorScheme, onLight ? .light : .dark)
        .animation(nil, value: onLight)
        .onChange(of: ObjectIdentifier(browser)) { _, _ in
            surface.browserDidChange(browser)
        }
    }
}

private struct IslandAddressMenu: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var hasLink: Bool {
        browser.activeTab.flatMap { coordinator.linkURL(for: $0) } != nil
    }

    private var pastedText: String? {
        let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    var body: some View {
        Button {
            coordinator.copyCurrentURL()
        } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
        .disabled(!hasLink)

        if let pastedText {
            Button {
                coordinator.openPalette(seed: pastedText)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }

            if Omnibox.location(for: pastedText) == nil {
                Button {
                    browser.handleAddressInput(pastedText)
                } label: {
                    Label("Paste and Search", systemImage: "magnifyingglass")
                }
            } else {
                Button {
                    browser.handleAddressInput(pastedText)
                } label: {
                    Label("Paste and Go", systemImage: "arrow.right.doc.on.clipboard")
                }
            }
        }

        Divider()

        Button {
            coordinator.focusAddressBar()
        } label: {
            Label("Open Location…", systemImage: "magnifyingglass")
        }
    }
}

private struct IslandAddress: View {
    let tab: BrowserTab?
    let resting: AskRestingContent?
    let notice: ChromeNotice
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var onLight

    private var showsFullAddress: Bool {
        guard let tab else { return false }
        return tab.context.settings.showsFullAddress || tab.usesDeveloperMode
    }

    private var label: String {
        guard let tab, !ChromeBand.showsStartPage(for: tab) else {
            return String(localized: "Search or enter website")
        }
        if tab.internalPage != nil {
            return tab.title
        }
        if showsFullAddress {
            return tab.urlString
        }
        guard let host = URL(string: tab.urlString)?.host(percentEncoded: false) else {
            return tab.urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var isPlaceholder: Bool {
        guard let tab else { return true }
        return ChromeBand.showsStartPage(for: tab)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                switch resting {
                case .notice(let message, let symbol):
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(notice.isWarning ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.foreground))
                            .noticePop(notice)
                    }
                    Text(verbatim: message)
                        .font(Theme.Font.control)
                        .lineLimit(1)
                case .transcript(let live):
                    Group {
                        if live.isEmpty {
                            Text("Listening…")
                        } else {
                            Text(verbatim: live)
                        }
                    }
                    .font(Theme.Font.control)
                    .lineLimit(1)
                    .truncationMode(.head)
                case .agent(let message):
                    Text(verbatim: message)
                        .font(Theme.Font.control)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .status(let status):
                    Text(verbatim: status)
                        .font(Theme.Font.control)
                        .foregroundStyle(Theme.warning)
                        .lineLimit(1)
                        .truncationMode(.head)
                default:
                    if tab?.isLoading == true {
                        Spinner(size: 12)
                    } else if let favicon = tab?.favicon, !isPlaceholder {
                        FaviconImage(image: favicon)
                            .frame(width: 14, height: 14)
                    }
                    Text(label)
                        .font(Theme.Font.control)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(ChromeInk.glyph(onLight: onLight, hovering: hovering, subdued: resting == nil && isPlaceholder))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .noticeWash(notice, isShowing: resting?.isNotice ?? false, in: Capsule())
            .hoverBackground(isActive: hovering, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Open Location…"))
        .onHover { hovering = $0 }
    }
}
