// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct WindowStylePicker: View {
    let isMinimal: Bool
    let loomStyle: LoomStyle
    let usesWebsiteTint: Bool
    let tintsSelectedTab: Bool
    let onSelect: (Bool) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppearanceThumbnailMetrics.spacing) {
                cards
            }
            LazyVGrid(
                columns: AppearanceThumbnailMetrics.columns,
                spacing: AppearanceThumbnailMetrics.spacing
            ) {
                cards
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var cards: some View {
        PreviewChoiceCard(label: "Standard", isSelected: !isMinimal, action: { onSelect(false) }) {
            LoomStyleThumbnail(
                style: loomStyle,
                usesWebsiteTint: usesWebsiteTint,
                tintsSelectedTab: tintsSelectedTab
            )
        }
        PreviewChoiceCard(label: "Minimal", isSelected: isMinimal, action: { onSelect(true) }) {
            MinimalStyleThumbnail()
        }
    }
}

private struct MinimalStyleThumbnail: View {
    private let ink = Color.white
    private let orange = Color(red: 0.95, green: 0.43, blue: 0.18)
    private let magenta = Color(red: 0.72, green: 0.26, blue: 0.46)
    private let purple = Color(red: 0.38, green: 0.14, blue: 0.58)

    private var cards: [[Color]] {
        [[orange, magenta], [magenta, purple], [purple, Color(red: 0.24, green: 0.2, blue: 0.62)]]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.21, green: 0.09, blue: 0.25),
                    Color(red: 0.10, green: 0.06, blue: 0.19),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(colors: [orange, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 26)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(ink.opacity(0.92)).frame(width: 40, height: 4)
                            Capsule().fill(ink.opacity(0.6)).frame(width: 28, height: 2)
                        }
                        .padding(7)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(ink.opacity(0.4)).frame(width: 74, height: 2)
                    Capsule().fill(ink.opacity(0.4)).frame(width: 66, height: 2)
                    Capsule().fill(ink.opacity(0.4)).frame(width: 70, height: 2)
                    HStack(spacing: 3) {
                        ForEach(cards, id: \.self) { pair in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .opacity(0.6)
                                .frame(height: 9)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 7)
                .padding(.top, 6)

                Spacer(minLength: 0)
            }

            MinimalPreviewPill(ink: ink, accent: orange)
                .padding(.bottom, 4)
        }
    }
}

private struct MinimalPreviewPill: View {
    let ink: Color
    let accent: Color

    var body: some View {
        HStack(spacing: 2.5) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .strokeBorder(ink.opacity(0.85), lineWidth: 0.7)
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(ink.opacity(0.25))
                .frame(width: 0.5, height: 4)
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
                .opacity(0.45)
            Image(systemName: "arrow.clockwise")
            HStack(spacing: 2) {
                Circle().fill(accent).frame(width: 2.5, height: 2.5)
                Capsule().fill(ink.opacity(0.6)).frame(width: 13, height: 1.8)
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "ellipsis")
            Image(systemName: "sidebar.right")
        }
        .font(.system(size: 3.5, weight: .bold))
        .foregroundStyle(ink.opacity(0.8))
        .padding(.horizontal, 4.5)
        .frame(width: 70, height: 10)
        .background {
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.33, green: 0.15, blue: 0.43),
                        Color(red: 0.23, green: 0.11, blue: 0.35),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [ink.opacity(0.3), ink.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

private struct LoomStyleThumbnail: View {
    let style: LoomStyle
    let usesWebsiteTint: Bool
    let tintsSelectedTab: Bool

    private var palette: ThemeThumbnailPalette {
        ThemeThumbnailPalette(
            id: .dark,
            backdrop: .clear,
            chrome: .clear,
            canvas: Color(red: 0.055, green: 0.06, blue: 0.07),
            surface: Color.white.opacity(0.13),
            primary: Color.white.opacity(0.76),
            secondary: Color.white.opacity(0.42),
            accent: Color(red: 0.25, green: 0.92, blue: 0.38)
        )
    }

    private var chromeInk: Color {
        style == .standard && !usesWebsiteTint
            ? Color.black.opacity(0.66)
            : Color.white.opacity(0.78)
    }

    var body: some View {
        AppearanceBrowserThumbnail(
            palette: palette,
            chromeInk: chromeInk,
            tintsSelectedTab: tintsSelectedTab
        ) {
            ZStack {
                LoomPreviewWallpaper()
                LoomPreviewChrome(style: style, usesWebsiteTint: usesWebsiteTint)
            }
        }
    }
}

private struct LoomPreviewWallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.62, blue: 0.86),
                Color(red: 0.16, green: 0.46, blue: 0.31),
                Color(red: 0.10, green: 0.18, blue: 0.12),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.52))
                    .frame(width: 34, height: 34)
                    .blur(radius: 6)
                    .offset(x: 32, y: -20)

                Ellipse()
                    .fill(Color(red: 0.33, green: 0.62, blue: 0.18).opacity(0.72))
                    .frame(width: 130, height: 40)
                    .blur(radius: 5)
                    .offset(x: -14, y: 29)
            }
        }
        .clipped()
    }
}

private struct LoomPreviewChrome: View {
    let style: LoomStyle
    let usesWebsiteTint: Bool

    var body: some View {
        switch style {
        case .standard:
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)

                if usesWebsiteTint {
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.43, blue: 0.18)
                                .opacity(0.90),
                            Color(red: 0.38, green: 0.14, blue: 0.58)
                                .opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color(white: 0.94).opacity(0.34)
                }
            }
        case .transparent:
            Color.clear
                .glassEffect(
                    .clear.tint(
                        usesWebsiteTint
                            ? Color(red: 0.76, green: 0.24, blue: 0.56).opacity(0.22)
                            : Color.white.opacity(0.035)
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }
}

struct LoomTransparencyControl: View {
    @Binding var opacity: Double

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: "capsule.on.rectangle")
                    .foregroundStyle(.secondary)

                LoomTransparencySnapSlider(opacity: $opacity)

                Image(systemName: "capsule.on.rectangle.fill")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("More transparent")
                Spacer()
                Text("Less transparent")
            }
            .font(Theme.Font.micro)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .settingsSurface(
            isLifted: true,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
    }
}

private struct LoomTransparencySnapSlider: View {
    private static let snapTolerance = 0.04

    @Binding var opacity: Double
    @State private var snappedStop: Double?

    var body: some View {
        VStack(spacing: 1) {
            Slider(value: $opacity, in: 0...1)
                .tint(Theme.systemAccent)
                .accessibilityLabel("Window transparency")
                .accessibilityValue(Text(opacity, format: .percent))

            HStack(spacing: 0) {
                LoomTransparencySnapDot(isSelected: opacity == 0)
                Spacer(minLength: 0)
                LoomTransparencySnapDot(isSelected: opacity == 0.5)
                Spacer(minLength: 0)
                LoomTransparencySnapDot(isSelected: opacity == 1)
            }
            .padding(.horizontal, 7)
        }
        .onChange(of: opacity) { _, newValue in
            let stop = snapStop(for: newValue)
            if stop != snappedStop {
                snappedStop = stop
                if stop != nil {
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .alignment,
                        performanceTime: .now
                    )
                }
            }
            if let stop, newValue != stop {
                opacity = stop
            }
        }
    }

    private func snapStop(for value: Double) -> Double? {
        if value <= Self.snapTolerance {
            return 0
        }
        if abs(value - 0.5) <= Self.snapTolerance {
            return 0.5
        }
        if value >= 1 - Self.snapTolerance {
            return 1
        }
        return nil
    }
}

private struct LoomTransparencySnapDot: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? Theme.systemAccent : Color.primary.opacity(0.36))
            .frame(width: 4, height: 4)
            .animation(Theme.Motion.quick, value: isSelected)
            .accessibilityHidden(true)
    }
}
