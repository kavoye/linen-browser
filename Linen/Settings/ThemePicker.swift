// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

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
        HStack(spacing: 12) {
            ForEach(AppearanceMode.allCases) { mode in
                ThemeThumbnailCard(
                    mode: mode,
                    isSelected: mode == selection
                ) {
                    onSelect(mode)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ThemeThumbnailCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    private static let width: CGFloat = 108
    private static let height: CGFloat = 68

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                thumbnail

                Text(mode.label)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .frame(width: Self.width, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .animation(Theme.Motion.quick, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnail: some View {
        let palettes = ThemeThumbnailPalette.palettes(for: mode)
        return ZStack(alignment: .leading) {
            ForEach(Array(palettes.enumerated()), id: \.element.id) { index, palette in
                ThemeThumbnailWindow(palette: palette)
                    .frame(width: Self.width, height: Self.height)
                    .clipShape(
                        Slice(
                            start: CGFloat(index) / CGFloat(palettes.count),
                            end: CGFloat(index + 1) / CGFloat(palettes.count)
                        )
                    )
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected
                    ? Theme.systemAccent.opacity(0.95)
                    : Color.primary.opacity(hovering ? 0.22 : 0.11),
                lineWidth: isSelected ? 2 : 1
            )
        }
        .shadow(
            color: .black.opacity(hovering || isSelected ? 0.26 : 0.18),
            radius: hovering || isSelected ? 7 : 4,
            y: hovering || isSelected ? 3 : 2
        )
        .scaleEffect(hovering ? 1.015 : 1)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
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
        ZStack {
            palette.backdrop

            LinearGradient(
                colors: [
                    palette.accent.opacity(0.16),
                    Color.white.opacity(0.055),
                    Color.black.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 4) {
                ThemeThumbnailSidebar(palette: palette)
                    .frame(width: 27)

                ThemeThumbnailContent(palette: palette)
            }
            .padding(5)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
            .allowsHitTesting(false)
        }
    }
}

private struct ThemeThumbnailSidebar: View {
    let palette: ThemeThumbnailPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Circle().fill(Color.red.opacity(0.82))
                Circle().fill(Color.yellow.opacity(0.82))
                Circle().fill(Color.green.opacity(0.82))
            }
            .frame(width: 13, height: 3)

            Capsule()
                .fill(palette.secondary.opacity(0.70))
                .frame(width: 15, height: 2)

            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 2) {
                    Circle()
                        .fill(index == 1 ? palette.accent : palette.secondary)
                        .frame(width: 3, height: 3)
                    Capsule()
                        .fill(palette.secondary.opacity(index == 1 ? 0.82 : 0.52))
                        .frame(height: 2)
                }
            }

            Spacer(minLength: 0)

            Capsule()
                .fill(palette.secondary.opacity(0.55))
                .frame(width: 12, height: 2)
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.chrome.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.15), radius: 2, x: 1, y: 1)
    }
}

private struct ThemeThumbnailContent: View {
    let palette: ThemeThumbnailPalette

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Capsule()
                    .fill(palette.surface.opacity(0.92))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .frame(height: 8)

                Circle()
                    .fill(palette.surface)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.canvas)
                    .overlay { ThemeThumbnailPage(palette: palette) }
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.chrome.opacity(0.90))
                    .frame(width: 13)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(palette.primary.opacity(0.50))
                            .frame(width: 7, height: 2)
                            .padding(.top, 5)
                    }
            }
        }
    }
}

private struct ThemeThumbnailPage: View {
    let palette: ThemeThumbnailPalette

    var body: some View {
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
}
