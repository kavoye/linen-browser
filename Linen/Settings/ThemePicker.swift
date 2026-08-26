// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum AppearanceThumbnailMetrics {
    static let width: CGFloat = 108
    static let height: CGFloat = 68
    static let spacing: CGFloat = 12

    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: width, maximum: width), spacing: spacing, alignment: .top)]
    }
}

struct ThemeThumbnailPalette: Equatable {
    enum Identifier: Hashable {
        case light
        case dark
    }

    let id: Identifier
    let backdrop: Color
    let chrome: Color
    let canvas: Color
    let surface: Color
    let primary: Color
    let secondary: Color
    let accent: Color

    static let light = ThemeThumbnailPalette(
        id: .light,
        backdrop: Color(red: 0.88, green: 0.90, blue: 0.94),
        chrome: Color(white: 0.91),
        canvas: Color(white: 0.985),
        surface: Color(white: 0.90),
        primary: Color(white: 0.28),
        secondary: Color(white: 0.63),
        accent: Color(red: 0.18, green: 0.48, blue: 0.94)
    )

    static let dark = ThemeThumbnailPalette(
        id: .dark,
        backdrop: Color(red: 0.07, green: 0.08, blue: 0.11),
        chrome: Color(white: 0.16),
        canvas: Color(white: 0.105),
        surface: Color(white: 0.23),
        primary: Color(white: 0.78),
        secondary: Color(white: 0.43),
        accent: Color(red: 0.26, green: 0.57, blue: 1.0)
    )

    static func palettes(for mode: AppearanceMode) -> [ThemeThumbnailPalette] {
        switch mode {
        case .system:
            [.light, .dark]
        case .light:
            [.light]
        case .dark:
            [.dark]
        }
    }
}

struct ThemePicker: View {
    let selection: AppearanceMode
    let onSelect: (AppearanceMode) -> Void

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
        ForEach(AppearanceMode.allCases) { mode in
            ThemeThumbnailCard(
                mode: mode,
                isSelected: mode == selection
            ) {
                onSelect(mode)
            }
        }
    }
}

private struct ThemeThumbnailCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PreviewChoiceCard(label: mode.label, isSelected: isSelected, action: action) {
            thumbnail
        }
    }

    private var thumbnail: some View {
        let palettes = ThemeThumbnailPalette.palettes(for: mode)
        return ZStack(alignment: .leading) {
            ForEach(Array(palettes.enumerated()), id: \.element.id) { index, palette in
                ThemeThumbnailWindow(palette: palette)
                    .frame(
                        width: AppearanceThumbnailMetrics.width,
                        height: AppearanceThumbnailMetrics.height
                    )
                    .clipShape(
                        Slice(
                            start: CGFloat(index) / CGFloat(palettes.count),
                            end: CGFloat(index + 1) / CGFloat(palettes.count)
                        )
                    )
            }
        }
    }
}

private struct Slice: Shape {
    let start: CGFloat
    let end: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX + rect.width * start,
            y: rect.minY,
            width: rect.width * (end - start),
            height: rect.height
        ))
    }
}

private struct ThemeThumbnailWindow: View {
    let palette: ThemeThumbnailPalette

    var body: some View {
        AppearanceBrowserThumbnail(palette: palette, chromeInk: palette.primary) {
            ZStack {
                palette.backdrop

                LinearGradient(
                    colors: [
                        palette.accent.opacity(0.12),
                        Color.white.opacity(0.055),
                        Color.black.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct AppearanceBrowserThumbnail<Backdrop: View>: View {
    let palette: ThemeThumbnailPalette
    let chromeInk: Color
    let tintsSelectedTab: Bool
    let backdrop: Backdrop

    init(
        palette: ThemeThumbnailPalette,
        chromeInk: Color,
        tintsSelectedTab: Bool = false,
        @ViewBuilder backdrop: () -> Backdrop
    ) {
        self.palette = palette
        self.chromeInk = chromeInk
        self.tintsSelectedTab = tintsSelectedTab
        self.backdrop = backdrop()
    }

    var body: some View {
        ZStack {
            backdrop

            AppearanceBrowserPage(palette: palette)
                .padding(.top, 14)
                .padding(.leading, 29)
                .padding(.trailing, 5)
                .padding(.bottom, 5)

            AppearanceBrowserChrome(
                ink: chromeInk,
                secondaryInk: palette.secondary,
                accent: palette.accent,
                tintsSelectedTab: tintsSelectedTab
            )
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.13), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 13)
            .allowsHitTesting(false)
        }
    }
}

private struct AppearanceBrowserPage: View {
    let palette: ThemeThumbnailPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(palette.canvas)
            .overlay {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(palette.primary.opacity(0.72))
                        .frame(width: 28, height: 3)

                    Capsule()
                        .fill(palette.secondary.opacity(0.55))
                        .frame(width: 38, height: 2)

                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(index == 0 ? palette.accent.opacity(0.34) : palette.surface)
                                .frame(height: 11)
                        }
                    }

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(palette.surface.opacity(0.92))
                        .frame(height: 8)
                }
                .padding(6)
            }
            .shadow(color: .black.opacity(0.23), radius: 3, y: 1)
    }
}

private struct AppearanceBrowserChrome: View {
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let tintsSelectedTab: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppearanceBrowserSidebar(
                ink: ink,
                secondaryInk: secondaryInk,
                accent: accent,
                tintsSelectedTab: tintsSelectedTab
            )
                .padding(.leading, 6)
                .padding(.top, 17)

            AppearanceTrafficLights()
                .frame(width: 13, height: 3)
                .padding(.leading, 6)
                .padding(.top, 6)

            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 4, weight: .bold))
            .foregroundStyle(ink.opacity(0.64))
            .frame(width: 12, height: 7)
            .padding(.leading, 31.5)
            .padding(.top, 4)

            Capsule()
                .fill(ink.opacity(0.18))
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
                .frame(width: 40, height: 7)
                .padding(.top, 4)
                .padding(.leading, 46)

            Circle()
                .fill(ink.opacity(0.20))
                .frame(width: 7, height: 7)
                .padding(.top, 4)
                .padding(.leading, 95)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AppearanceBrowserSidebar: View {
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let tintsSelectedTab: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule()
                .fill(ink.opacity(0.60))
                .frame(width: 15, height: 2)

            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 2) {
                    Circle()
                        .fill(
                            index == 1 && tintsSelectedTab
                                ? accent
                                : secondaryInk.opacity(0.76)
                        )
                        .frame(width: 3, height: 3)
                    Capsule()
                        .fill(ink.opacity(index == 1 ? 0.78 : 0.43))
                        .frame(width: index == 1 ? 10 : 12, height: 2)
                }
                .padding(.horizontal, 1.5)
                .frame(height: 6)
                .background {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            index == 1
                                ? (tintsSelectedTab ? accent.opacity(0.58) : ink.opacity(0.10))
                                : Color.clear
                        )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Circle()
                    .strokeBorder(ink.opacity(0.48), lineWidth: 1)
                    .frame(width: 4, height: 4)
                Capsule()
                    .fill(ink.opacity(0.48))
                    .frame(width: 11, height: 2)
            }
        }
        .frame(width: 20, height: 45, alignment: .topLeading)
    }
}

private struct AppearanceTrafficLights: View {
    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(Color.red.opacity(0.86))
            Circle().fill(Color.yellow.opacity(0.86))
            Circle().fill(Color.green.opacity(0.86))
        }
    }
}
