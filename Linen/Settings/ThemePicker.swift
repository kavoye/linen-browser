// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ThemeThumbnailPalette: Equatable {
    let background: Color
    let chrome: Color
    let content: Color

    static let light = ThemeThumbnailPalette(
        background: Color(white: 0.96),
        chrome: Color(white: 0.88),
        content: Color(white: 0.78)
    )

    static let dark = ThemeThumbnailPalette(
        background: Color(white: 0.16),
        chrome: Color(white: 0.28),
        content: Color(white: 0.38)
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
            VStack(spacing: 8) {
                thumbnail

                HStack(spacing: 5) {
                    SelectionDot(isSelected: isSelected)

                    Text(mode.label)
                        .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnail: some View {
        let palettes = ThemeThumbnailPalette.palettes(for: mode)
        return ZStack(alignment: .leading) {
            ForEach(Array(palettes.enumerated()), id: \.offset) { index, palette in
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Wash.emphasis : (hovering ? Theme.Wash.outline : Theme.Wash.hairline),
                    lineWidth: isSelected ? 2 : 1
                )
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
        HStack(spacing: 0) {
            palette.chrome
                .frame(width: 26)

            ZStack(alignment: .topLeading) {
                palette.background

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.chrome)
                        .frame(height: 9)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.content)
                        .frame(width: 46, height: 4)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.content)
                        .frame(width: 30, height: 4)
                }
                .padding(8)
            }
        }
    }
}

private struct SelectionDot: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .strokeBorder(isSelected ? Theme.Wash.mark : Theme.Wash.outline, lineWidth: 1)
            .background {
                Circle().fill(isSelected ? Theme.Wash.mark : Theme.Wash.none)
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
