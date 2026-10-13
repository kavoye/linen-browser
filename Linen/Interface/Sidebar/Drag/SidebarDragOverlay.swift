// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SidebarDragOverlay: View {
    let browser: BrowserModel
    let model: SidebarDragModel

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.windowColorScheme) private var windowColorScheme

    @State private var float = SidebarDragFloat()

    var body: some View {
        GeometryReader { proxy in
            if let drag = model.drag, model.floatOrigin == nil {
                let origin = proxy.frame(in: .global).origin
                SidebarDragStack(drag: drag, browser: browser)
                    .frame(width: drag.origin.width, height: drag.origin.height)
                    .scaleEffect(drag.landing ? 1 : SidebarDragGhost.liftScale(style: sidebarStyle))
                    .offset(
                        x: model.listOriginInWindow.x - origin.x + chipX(drag),
                        y: model.listOriginInWindow.y - origin.y + chipY(drag)
                    )
            }
        }
        .allowsHitTesting(false)
        .onChange(of: model.floatOrigin) { _, topLeft in
            guard let topLeft, let drag = model.drag else {
                float.hide()
                return
            }
            float.show(drag.items, at: topLeft, size: drag.origin.size, landing: drag.landing) {
                SidebarDragFloatContent(model: model, browser: browser)
                    .environment(\.sidebarStyle, sidebarStyle)
                    .environment(\.windowColorScheme, windowColorScheme)
            }
        }
        .onDisappear { float.hide() }
    }

    private func chipX(_ drag: SidebarDrag) -> CGFloat {
        guard !drag.landing else { return drag.origin.minX }
        return drag.origin.minX + drag.translation.width
    }

    private func chipY(_ drag: SidebarDrag) -> CGFloat {
        guard !drag.landing else { return model.frames[drag.lead]?.minY ?? drag.origin.minY }
        return drag.origin.minY + drag.translation.height
    }
}

private struct SidebarDragFloatContent: View {
    let model: SidebarDragModel
    let browser: BrowserModel

    @Environment(\.sidebarStyle) private var sidebarStyle

    var body: some View {
        if let drag = model.drag {
            SidebarDragStack(drag: drag, browser: model.chipBrowser ?? browser)
                .frame(width: drag.origin.width, height: drag.origin.height)
                .scaleEffect(drag.landing ? 1 : SidebarDragGhost.liftScale(style: sidebarStyle))
        }
    }
}

struct PaneDragOverlay: View {
    let browser: BrowserModel
    let model: SidebarDragModel

    private static let size = CGSize(width: 190, height: 32)

    var body: some View {
        GeometryReader { proxy in
            if let id = model.carriedPaneID {
                let origin = proxy.frame(in: .global).origin
                SidebarDragChip(item: .tab(id), browser: browser)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .offset(
                        x: model.panePointInWindow.x - origin.x - Self.size.width / 2,
                        y: model.panePointInWindow.y - origin.y - Self.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

struct SidebarDragStack: View {
    let drag: SidebarDrag
    let browser: BrowserModel

    private static let step: CGFloat = 4

    private var behind: [SidebarItem] {
        Array(drag.items.filter { $0 != drag.lead }.prefix(2))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(behind.enumerated()).reversed(), id: \.element) { index, item in
                SidebarDragChip(item: item, browser: browser)
                    .offset(
                        x: CGFloat(index + 1) * Self.step,
                        y: CGFloat(index + 1) * Self.step
                    )
                    .opacity(1 - Double(index + 1) * 0.22)
            }
            SidebarDragChip(item: drag.lead, browser: browser)
        }
        .overlay(alignment: .topTrailing) {
            if !drag.isSingle {
                Text(drag.items.count, format: .number)
                    .font(Theme.Font.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Theme.accent, in: Capsule())
                    .offset(x: 5, y: -6)
            }
        }
    }
}

struct SidebarDragChip: View {
    let item: SidebarItem
    let browser: BrowserModel

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.windowColorScheme) private var windowColorScheme

    private var glass: Glass {
        .clear.tint(Theme.controlSurface.opacity(SidebarDragGhost.chipFillOpacity))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        content
            .padding(.horizontal, SidebarMetrics.rowContentPadding(style: sidebarStyle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(glass, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
            .environment(\.colorScheme, windowColorScheme)
            .shadow(color: .black.opacity(0.3), radius: 11, y: 5)
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .tab(let id):
            if let tab = browser.tab(id: id) {
                HStack(spacing: 8) {
                    TabIcon(tab: tab)
                    if sidebarStyle == .full {
                        Text(verbatim: tab.title)
                            .font(Theme.Font.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .folder(let id):
            if let folder = browser.folder(id: id) {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(folder.color.tint)
                    if sidebarStyle == .full {
                        Text(verbatim: folder.name)
                            .font(Theme.Font.control)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
