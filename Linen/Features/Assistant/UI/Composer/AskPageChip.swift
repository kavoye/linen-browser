// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct AskPageChip: View {
    static let contextFontSize: CGFloat = 10.5

    static func height(fontSize: CGFloat) -> CGFloat {
        let text = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: fontSize)).rounded(.up)
        return max((fontSize * 1.15).rounded(), text) + 2 * (fontSize * 0.24).rounded()
    }

    let title: String
    let icon: NSImage?
    var isAttached = false
    var isRasterised = false
    let fontSize: CGFloat
    var height: CGFloat?

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
                    FaviconImage(image: icon)
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
        .padding(.vertical, height == nil ? (fontSize * 0.24).rounded() : 0)
        .frame(height: height)
        .background(rasterisedFill, in: Capsule())
        .glassSurface(isEnabled: !isRasterised, in: Capsule())
    }

    private var rasterisedFill: AnyShapeStyle {
        guard isRasterised else { return AnyShapeStyle(.clear) }
        return AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
    }
}

struct AskPageChipView: View {
    @Environment(\.profileFavicons) private var profileFavicons
    private var favicons: FaviconLoader {
        profileFavicons ?? .shared
    }
    let title: String
    let host: String?
    var isAttached = false
    let fontSize: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        AskPageChip(title: title, icon: icon, isAttached: isAttached, fontSize: fontSize)
            .task(id: host) {
                guard let host else { return }
                if let hit = favicons.cached(for: host) {
                    icon = hit
                    return
                }
                icon = await favicons.load(forHost: host)
            }
    }
}
