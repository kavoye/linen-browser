// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct LoomStylePicker: View {
    let selection: LoomStyle
    let usesWebsiteTint: Bool
    let tintsSelectedTab: Bool
    let onSelect: (LoomStyle) -> Void

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
        ForEach(LoomStyle.allCases) { style in
            LoomStyleCard(
                style: style,
                usesWebsiteTint: usesWebsiteTint,
                tintsSelectedTab: tintsSelectedTab,
                isSelected: style == selection,
                action: { onSelect(style) }
            )
        }
    }
}

private struct LoomStyleCard: View {
    let style: LoomStyle
    let usesWebsiteTint: Bool
    let tintsSelectedTab: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PreviewChoiceCard(label: style.label, isSelected: isSelected, action: action) {
            LoomStyleThumbnail(
                style: style,
                usesWebsiteTint: usesWebsiteTint,
                tintsSelectedTab: tintsSelectedTab
            )
        }
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
