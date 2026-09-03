// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

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
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.34), radius: 26, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(_ tab: BrowserTab) -> some View {
        VStack(spacing: 8) {
            TabIcon(tab: tab, size: 18)
                .padding(4)
                .background(Self.controlFill, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
                .help(Text(verbatim: tab.title))

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
    let action: () -> Void

    static let extent: CGFloat = 20

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TabIcon(tab: tab, size: 13)
                .frame(width: Self.extent, height: Self.extent)
                .background(
                    Theme.accent.opacity(hovering ? 0.32 : 0.2),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.tight + 1, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Peeking at “\(tab.title)”"))
    }
}
