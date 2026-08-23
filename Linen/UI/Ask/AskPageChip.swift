// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct AskPageChip: View {
    let title: String
    let icon: NSImage?
    var isAttached = false
    var isRasterised = false
    let fontSize: CGFloat

    @Environment(\.colorScheme) private var scheme

    private var ink: Color {
        guard isRasterised else { return .primary }
        return scheme == .dark ? .white : .black
    }

    private var iconSize: CGFloat {
        (fontSize * 1.15).rounded()
    }

    private var iconRadius: CGFloat {
        max(2, min(Theme.Radius.tight, (iconSize * 0.25).rounded()))
    }

    var body: some View {
        HStack(spacing: (fontSize * 0.45).rounded()) {
            if isAttached {
                Image(systemName: "at")
                    .font(.system(size: fontSize * 0.95))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: iconRadius, style: .continuous))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: iconSize * 0.8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: iconSize, height: iconSize)

            Text(verbatim: title)
                .font(.system(size: fontSize))
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: fontSize * 14, alignment: .leading)
        }
        .padding(.horizontal, (fontSize * 0.55).rounded())
        .padding(.vertical, (fontSize * 0.24).rounded())
        .background(rasterisedFill, in: Capsule())
        .overlay {
            if isRasterised {
                Capsule().strokeBorder(Theme.Wash.strong, lineWidth: 0.5)
            }
        }
        .glassSurface(isEnabled: !isRasterised, in: Capsule())
    }

    private var rasterisedFill: AnyShapeStyle {
        guard isRasterised else { return AnyShapeStyle(.clear) }
        return AnyShapeStyle(ink.opacity(scheme == .dark ? 0.16 : 0.10))
    }
}

struct AskPageChipView: View {
    let title: String
    let host: String?
    var isAttached = false
    let fontSize: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        AskPageChip(title: title, icon: icon, isAttached: isAttached, fontSize: fontSize)
            .task(id: host) {
                guard let host else { return }
                if let hit = FaviconLoader.shared.cached(for: host) {
                    icon = hit
                    return
                }
                icon = await FaviconLoader.shared.load(forHost: host)
            }
    }
}
