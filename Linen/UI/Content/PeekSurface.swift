// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

struct PeekSurface: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private static let maximumWidth: CGFloat = 1220
    private static let controlWidth: CGFloat = 28
    private static let arrivalScale: CGFloat = 0.12

    static let controlFill = Color(white: 0.17)

    private var shown: BrowserTab? {
        coordinator.shownPeek
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let tab = shown {
                    Color.black.opacity(0.26)
                        .contentShape(Rectangle())
                        .onTapGesture { coordinator.closePeek() }
                        .transition(.opacity)

                    HStack(alignment: .top, spacing: 8) {
                        panel(tab)
                        controls(tab)
                    }
                    .frame(maxWidth: Self.maximumWidth)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .transition(
                        .scale(scale: Self.arrivalScale, anchor: anchor(in: proxy.size))
                            .combined(with: .opacity)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(shown != nil)
            .animation(coordinator.peek.isQuiet ? nil : Self.arrival, value: shown?.id)
        }
    }

    private static let arrival = Animation.spring(response: 0.34, dampingFraction: 0.84)

    /// The panel grows out of the link that opened it.
    private func anchor(in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        let origin = coordinator.peek.origin
        return UnitPoint(
            x: min(max(origin.x / size.width, 0), 1),
            y: min(max(origin.y / size.height, 0), 1)
        )
    }

    private func panel(_ tab: BrowserTab) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return WebViewRepresentable(
            webView: tab.webView,
            parksWhenIdle: true,
            onReady: { tab.webViewDidBecomeVisible() }
        )
            .background(tab.surfaceColor)
            .overlay {
                if !tab.hasPresentedContent {
                    tab.surfaceColor
                        .transition(.identity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                LinkPreview(
                    address: tab.hoveredLink?.absoluteString,
                    intent: coordinator.linkModifiers.contains(.command) ? .newTab : .open,
                    ground: tab.canvasColor
                )
                .id(tab.id)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.34), radius: 26, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(_ tab: BrowserTab) -> some View {
        VStack(spacing: 8) {
            PeekPageMenu(tab: tab, coordinator: coordinator)

            PeekControl(symbol: "xmark", help: "Close Peek") {
                coordinator.closePeek()
            }
            PeekControl(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Keep as a Tab"
            ) {
                coordinator.keepPeek()
            }
            PeekControl(symbol: "rectangle.split.2x1", help: "Keep Beside This Page") {
                coordinator.keepPeekBesideCurrentPage()
            }
        }
        .frame(width: Self.controlWidth)
    }
}

private struct PeekPageMenu: View {
    let tab: BrowserTab
    let coordinator: AppCoordinator

    @State private var hovering = false

    var body: some View {
        Menu {
            Button {
                tab.webView.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            Button {
                tab.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!tab.canGoBack)
            Button {
                tab.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .disabled(!tab.canGoForward)

            Divider()

            Button {
                coordinator.copyLink(for: tab)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            .disabled(coordinator.linkURL(for: tab) == nil)
        } label: {
            ZStack {
                TabIcon(tab: tab, size: 18, loadingColor: .white)
                    .environment(\.colorScheme, .dark)
                    .opacity(hovering ? 0 : 1)
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 26, height: 26)
            .background(PeekSurface.controlFill, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(hovering ? 0.28 : 0.1), lineWidth: 0.5)
            }
            .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text("Page Actions"))
        .accessibilityLabel(Text("Page Actions"))
    }
}

private struct PeekControl: View {
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.82))
                .frame(width: 26, height: 26)
                .background(PeekSurface.controlFill, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(hovering ? 0.28 : 0.1), lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PeekRowBadge: View {
    let tab: BrowserTab
    let coordinator: AppCoordinator

    static let extent: CGFloat = 20

    @State private var hovering = false

    private var isCollapsed: Bool { coordinator.peek.isCollapsed }
    private var showsToggleIcon: Bool { hovering || isCollapsed }
    private var toggleSymbol: String {
        coordinator.shownPeek == nil
            ? "arrow.up.left.and.arrow.down.right"
            : "arrow.down.right.and.arrow.up.left"
    }
    private var toggleLabel: LocalizedStringResource {
        coordinator.shownPeek == nil ? "Show Peek" : "Collapse Peek"
    }

    var body: some View {
        Button { coordinator.togglePeekVisibility() } label: {
            ZStack {
                TabIcon(tab: tab, size: 13)
                    .scaleEffect(showsToggleIcon ? 0.15 : 1)
                    .opacity(showsToggleIcon ? 0 : 1)
                Image(systemName: toggleSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(showsToggleIcon ? 1 : 0.15)
                    .opacity(showsToggleIcon ? 1 : 0)
            }
                .frame(width: Self.extent, height: Self.extent)
                .background(
                    Theme.accent.opacity(hovering ? 0.32 : 0.2),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.tight + 1, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.quick, value: isCollapsed)
        .animation(Theme.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
        .help(Text(toggleLabel))
        .accessibilityLabel(Text(toggleLabel))
        .accessibilityValue(Text(verbatim: tab.title))
        .contextMenu {
            Button(toggleLabel) { coordinator.togglePeekVisibility() }
            Divider()
            Button("Reload", systemImage: "arrow.clockwise") { tab.webView.reload() }
            Button("Back", systemImage: "chevron.left") { tab.goBack() }
                .disabled(!tab.canGoBack)
            Button("Forward", systemImage: "chevron.right") { tab.goForward() }
                .disabled(!tab.canGoForward)
            Button("Copy Link", systemImage: "doc.on.doc") { coordinator.copyLink(for: tab) }
                .disabled(coordinator.linkURL(for: tab) == nil)
            Divider()
            Button("Keep as a Tab", systemImage: "arrow.up.left.and.arrow.down.right") {
                activateOwner()
                coordinator.keepPeek()
            }
            Button("Keep Beside This Page", systemImage: "rectangle.split.2x1") {
                activateOwner()
                coordinator.keepPeekBesideCurrentPage()
            }
            Button("Close Peek", systemImage: "xmark", role: .destructive) {
                coordinator.closePeek()
            }
        }
    }

    private func activateOwner() {
        guard let id = coordinator.peek.ownerID, let owner = coordinator.browser.tab(id: id) else { return }
        coordinator.openTab(owner)
    }
}
