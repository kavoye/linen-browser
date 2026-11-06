// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

extension OnboardingUI {
    struct Stage: View {
        let isMinimal: Bool
        let step: OnboardingModel.Step?
        let extensionSymbols: [String]
        let windowSize: CGSize

        private static let morph: Animation = .spring(duration: 0.6, bounce: 0.1)
        private let cornerRadius: CGFloat = 12

        var body: some View {
            GeometryReader { proxy in
                let scale = windowSize.width > 0 ? proxy.size.width / windowSize.width : 1
                Replica(
                    isMinimal: isMinimal,
                    showsImport: showsImport,
                    extensionSymbols: extensionSymbols
                )
                .frame(width: windowSize.width, height: windowSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 34, y: 16)
            .animation(Self.morph, value: isMinimal)
            .animation(Self.morph, value: showsImport)
            .animation(Self.morph, value: extensionSymbols)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private var showsImport: Bool {
            guard let step else { return false }
            return step.rawValue >= OnboardingModel.Step.bookmarks.rawValue
        }
    }

    private struct SampleTab: Identifiable {
        let id: String
        let symbol: String
        let title: LocalizedStringResource
    }

    private enum Sample {
        static let host = "example.com"

        static let pinned: [SampleTab] = [
            .init(id: "inbox", symbol: "envelope", title: "Inbox"),
            .init(id: "calendar", symbol: "calendar", title: "Calendar"),
        ]

        static let tabs: [SampleTab] = [
            .init(id: "trip", symbol: "airplane", title: "Trip to Lisbon"),
            .init(id: "news", symbol: "newspaper", title: "Morning News"),
            .init(id: "recipes", symbol: "fork.knife", title: "Weeknight Recipes"),
            .init(id: "notes", symbol: "doc.text", title: "Project Notes"),
            .init(id: "playlist", symbol: "music.note", title: "Focus Playlist"),
        ]

        static var active: SampleTab {
            tabs[0]
        }

        static var count: Int {
            pinned.count + tabs.count
        }
    }

    private struct Replica: View {
        let isMinimal: Bool
        let showsImport: Bool
        let extensionSymbols: [String]

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            GeometryReader { proxy in
                let size = proxy.size
                let sidebarWidth = min(SidebarMetrics.defaultWidth, size.width * SidebarMetrics.maxWindowFraction)
                let inset = LoomChrome.canvasInset
                let canvas = isMinimal
                    ? CGRect(origin: .zero, size: size)
                    : CGRect(
                        x: sidebarWidth,
                        y: Theme.topBarHeight,
                        width: size.width - sidebarWidth - inset,
                        height: size.height - Theme.topBarHeight - inset
                    )
                let islandWidth = min(600, size.width - 28)

                ZStack(alignment: .topLeading) {
                    Color(nsColor: LoomChrome.sampledColor(nil, scheme: scheme))

                    ReplicaSidebar(showsImport: showsImport)
                        .frame(width: sidebarWidth, height: size.height)
                        .offset(x: isMinimal ? -sidebarWidth : 0)

                    ReplicaNavBar(extensionSymbols: extensionSymbols)
                        .frame(width: max(0, size.width - sidebarWidth), height: Theme.topBarHeight)
                        .offset(x: sidebarWidth)
                        .opacity(isMinimal ? 0 : 1)

                    SkeletonPage()
                        .frame(width: max(0, canvas.width), height: max(0, canvas.height))
                        .background(Theme.windowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: isMinimal ? 0 : LoomChrome.canvasRadius, style: .continuous))
                        .shadow(color: .black.opacity(isMinimal ? 0 : 0.18), radius: 12, y: 4)
                        .offset(x: canvas.minX, y: canvas.minY)

                    ReplicaIsland(extensionSymbols: extensionSymbols)
                        .frame(width: islandWidth, height: IslandBar.height)
                        .offset(
                            x: (size.width - islandWidth) / 2,
                            y: size.height - IslandBar.height - 14 + (isMinimal ? 0 : 80)
                        )
                        .opacity(isMinimal ? 1 : 0)

                    TrafficLights()
                        .offset(x: 14, y: Theme.topBarHeight / 2 - 6)
                        .opacity(isMinimal ? 0 : 1)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
    }

    private struct TrafficLights: View {
        var body: some View {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
            }
            .frame(width: 52, height: 12)
        }
    }

    private struct ReplicaSidebar: View {
        let showsImport: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: SidebarMetrics.rowIconSpacing) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: SidebarMetrics.rowIconSize)
                    Text("New Tab")
                        .font(Theme.Font.title)
                    Spacer(minLength: 0)
                    Text(verbatim: "⌘T")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: SidebarMetrics.rowHeight)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Sample.pinned) { tab in
                        ReplicaRow(symbol: tab.symbol, title: tab.title)
                    }

                    Capsule()
                        .fill(Theme.chrome(0.14))
                        .frame(height: 1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)

                    if showsImport {
                        ReplicaRow(symbol: "folder", title: "Imported Bookmarks", isHighlighted: true)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    }

                    ForEach(Sample.tabs) { tab in
                        ReplicaRow(symbol: tab.symbol, title: tab.title, isActive: tab.id == Sample.active.id)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)

                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { index in
                            SpaceDotGlyph(
                                symbol: "person.fill",
                                growth: index == 0 ? 1 : 0,
                                isHovered: false,
                                isHoverActive: false,
                                motion: .follow
                            )
                            .frame(width: 20, height: 28)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "text.menu")
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.top, Theme.topBarHeight)
            .padding(.bottom, 12)
            .padding(.leading, LoomChrome.canvasInset)
            .padding(.trailing, LoomChrome.canvasInset / 2)
        }
    }

    private struct ReplicaRow: View {
        let symbol: String
        let title: LocalizedStringResource
        var isActive = false
        var isHighlighted = false

        var body: some View {
            HStack(spacing: SidebarMetrics.rowIconSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.rowIconSize)
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(isActive || isHighlighted ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: SidebarMetrics.rowHeight)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
                        .fill(Theme.windowBackground.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                } else if isHighlighted {
                    RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
        }
    }

    private struct ReplicaNavBar: View {
        let extensionSymbols: [String]

        var body: some View {
            HStack(spacing: 6) {
                ReplicaGlyph(name: "chevron.left")
                ReplicaGlyph(name: "chevron.right", dimmed: true)
                ReplicaGlyph(name: "arrow.clockwise")

                Spacer(minLength: 8)

                ReplicaAddress(height: 36, cornerRadius: Theme.Radius.card, showsLock: true)
                    .frame(maxWidth: Theme.addressBarMaxWidth)

                Spacer(minLength: 8)

                ForEach(extensionSymbols, id: \.self) { symbol in
                    ReplicaGlyph(name: symbol)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                ReplicaGlyph(name: "sidebar.right")
            }
            .padding(.horizontal, 10)
        }
    }

    private struct ReplicaIsland: View {
        let extensionSymbols: [String]

        var body: some View {
            HStack(spacing: 2) {
                ReplicaGlyph(name: "\(Sample.count).square")
                divider
                ReplicaGlyph(name: "chevron.left")
                ReplicaGlyph(name: "chevron.right", dimmed: true)
                ReplicaGlyph(name: "arrow.clockwise")
                ReplicaAddress(height: 28, cornerRadius: 14, showsLock: false)
                divider
                ForEach(extensionSymbols, id: \.self) { symbol in
                    ReplicaGlyph(name: symbol)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                ReplicaGlyph(name: "ellipsis")
                ReplicaGlyph(name: "sidebar.right")
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .background {
                Capsule()
                    .fill(Theme.windowBackground)
                    .overlay {
                        Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
            }
        }

        private var divider: some View {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 4)
        }
    }

    private struct ReplicaGlyph: View {
        let name: String
        var dimmed = false

        var body: some View {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(dimmed ? 0.45 : 1)
                .frame(width: 30, height: 28)
        }
    }

    private struct ReplicaAddress: View {
        let height: CGFloat
        let cornerRadius: CGFloat
        let showsLock: Bool

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: showsLock ? "lock.fill" : Sample.active.symbol)
                    .font(.system(size: showsLock ? 9.5 : 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: Sample.host)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
            }
        }
    }

    private struct SkeletonPage: View {
        private static let paragraph: [CGFloat] = [1, 0.96, 0.99, 0.92, 0.6]

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Circle()
                        .fill(fill(0.1))
                        .frame(width: 26, height: 26)
                    bar(width: 96, height: 10, opacity: 0.1)
                    Spacer(minLength: 0)
                    ForEach(0..<3, id: \.self) { _ in
                        bar(width: 58, height: 8, opacity: 0.07)
                    }
                }
                .padding(.horizontal, 28)
                .frame(height: 64)

                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(fill(0.07))
                        .frame(height: 240)

                    VStack(alignment: .leading, spacing: 12) {
                        bar(width: 420, height: 20, opacity: 0.12)
                        bar(width: 260, height: 20, opacity: 0.12)
                    }
                    .padding(.top, 32)

                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 11) {
                            ForEach(Array(Self.paragraph.enumerated()), id: \.offset) { _, fraction in
                                bar(width: proxy.size.width * fraction, height: 9, opacity: 0.07)
                            }
                        }
                    }
                    .frame(height: 96)
                    .padding(.top, 26)

                    HStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(fill(0.05))
                                .frame(height: 132)
                        }
                    }
                    .padding(.top, 20)
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 40)
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
        }

        private func fill(_ opacity: Double) -> Color {
            Color.primary.opacity(opacity)
        }

        private func bar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
            Capsule()
                .fill(fill(opacity))
                .frame(width: width, height: height)
        }
    }
}
