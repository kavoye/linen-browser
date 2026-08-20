// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

@MainActor
@Observable
final class TabPreviewModel {
    struct Shown {
        let tab: BrowserTab
        var anchor: CGRect
    }

    private(set) var shown: Shown?

    private static let showDelay: Duration = .milliseconds(500)
    private static let retargetDelay: Duration = .milliseconds(120)
    private static let hideDelay: Duration = .milliseconds(80)

    private var hoveredTabID: UUID?
    private var pending: Task<Void, Never>?
    private var isSuppressed = false

    func hover(_ tab: BrowserTab, anchor: CGRect) {
        guard !isSuppressed else { return }
        hoveredTabID = tab.id
        pending?.cancel()
        let delay = shown == nil ? Self.showDelay : Self.retargetDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.hoveredTabID == tab.id else { return }
            self.show(tab, anchor: anchor)
        }
    }

    func unhover(_ tabID: UUID) {
        guard hoveredTabID == tabID else { return }
        hoveredTabID = nil
        pending?.cancel()
        guard shown != nil else {
            pending = nil
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self, self.hoveredTabID == nil else { return }
            self.shown = nil
        }
    }

    func moved(_ tabID: UUID, anchor: CGRect) {
        guard shown?.tab.id == tabID else { return }
        shown?.anchor = anchor
    }

    func dismiss() {
        hoveredTabID = nil
        pending?.cancel()
        pending = nil
        shown = nil
    }

    func beginSuppression() {
        isSuppressed = true
        dismiss()
    }

    func endSuppression() {
        isSuppressed = false
    }

    private func show(_ tab: BrowserTab, anchor: CGRect) {
        tab.refreshPreview()
        if shown == nil {
            withAnimation(Theme.Motion.quick) {
                shown = Shown(tab: tab, anchor: anchor)
            }
        } else {
            shown = Shown(tab: tab, anchor: anchor)
        }
    }
}

struct TabPreviewOverlay: View {
    let browser: BrowserModel
    let model: TabPreviewModel

    @State private var cardSize: CGSize = .zero

    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            if let shown = model.shown,
               browser.tabs.contains(where: { $0.id == shown.tab.id }) {
                let origin = proxy.frame(in: .global).origin
                let y = min(
                    max(shown.anchor.midY - origin.y - cardSize.height / 2, Self.margin),
                    max(proxy.size.height - cardSize.height - Self.margin, Self.margin)
                )
                TabPreviewCard(tab: shown.tab)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                    .offset(x: shown.anchor.maxX - origin.x + Self.gap, y: y)
                    .opacity(cardSize == .zero ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TabPreviewCard: View {
    let tab: BrowserTab

    @State private var memoryBytes: UInt64?

    private static let width: CGFloat = 252
    private static let imageHeight: CGFloat = 150

    private var isAsleep: Bool {
        TabIcon.isAsleep(tab.reclaimState)
    }

    private var host: String {
        URL(string: tab.urlString)?.host() ?? ""
    }

    private var memoryLabel: String? {
        guard let memoryBytes else { return nil }
        return Int64(memoryBytes).formatted(.byteCount(style: .memory))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview = tab.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.width, height: Self.imageHeight, alignment: .top)
                    .clipped()
                    .saturation(isAsleep ? 0 : 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tab.title)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: false)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if !host.isEmpty {
                        Text(verbatim: host)
                            .font(Theme.Font.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let memoryLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 9))
                            Text(verbatim: memoryLabel)
                                .font(Theme.Font.caption)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: Self.width)
        .background(Theme.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.Wash.selection, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .task(id: tab.id) {
            while !Task.isCancelled {
                memoryBytes = WebProcessFootprint.bytes(of: tab.webView)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
