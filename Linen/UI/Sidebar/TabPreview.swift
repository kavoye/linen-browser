// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

@MainActor
@Observable
final class TabPreviewModel {
    enum Subject {
        case tab(BrowserTab)
        case folder(TabFolder, [BrowserTab])
        case split(TabSplit, [BrowserTab])

        var id: UUID {
            switch self {
            case .tab(let tab):
                tab.id
            case .folder(let folder, _):
                folder.id
            case .split(_, let panes):
                panes.first?.id ?? UUID()
            }
        }
    }

    struct Shown {
        let subject: Subject
        var anchor: CGRect
    }

    private(set) var shown: Shown?

    private static let showDelay: Duration = .milliseconds(500)
    private static let retargetDelay: Duration = .milliseconds(120)
    private static let hideDelay: Duration = .milliseconds(80)

    private var hoveredID: UUID?
    private var pending: Task<Void, Never>?
    private var isSuppressed = false

    func hover(_ subject: Subject, anchor: CGRect) {
        guard !isSuppressed else { return }
        let id = subject.id
        hoveredID = id
        pending?.cancel()
        let delay = shown == nil ? Self.showDelay : Self.retargetDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.hoveredID == id else { return }
            self.show(subject, anchor: anchor)
        }
    }

    func hover(_ tab: BrowserTab, anchor: CGRect) {
        hover(.tab(tab), anchor: anchor)
    }

    func unhover(_ id: UUID) {
        guard hoveredID == id else { return }
        hoveredID = nil
        pending?.cancel()
        guard shown != nil else {
            pending = nil
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self, self.hoveredID == nil else { return }
            self.shown = nil
        }
    }

    func moved(_ id: UUID, anchor: CGRect) {
        guard shown?.subject.id == id else { return }
        shown?.anchor = anchor
    }

    func dismiss() {
        hoveredID = nil
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

    private func show(_ subject: Subject, anchor: CGRect) {
        if case .tab(let tab) = subject {
            tab.refreshPreview()
        }
        if shown == nil {
            withAnimation(Theme.Motion.quick) {
                shown = Shown(subject: subject, anchor: anchor)
            }
        } else {
            shown = Shown(subject: subject, anchor: anchor)
        }
    }
}

struct TabPreviewOverlay: View {
    let browser: BrowserModel
    let model: TabPreviewModel
    let sidebarEdge: CGFloat

    @State private var cardSize: CGSize = .zero

    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            if let shown = model.shown, isStillThere(shown.subject) {
                let origin = proxy.frame(in: .global).origin
                let y = min(
                    max(shown.anchor.midY - origin.y - cardSize.height / 2, Self.margin),
                    max(proxy.size.height - cardSize.height - Self.margin, Self.margin)
                )
                TabPreviewCard(subject: shown.subject)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                    .offset(
                        x: max(shown.anchor.maxX - origin.x, sidebarEdge) + Self.gap,
                        y: y
                    )
                    .opacity(cardSize == .zero ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func isStillThere(_ subject: TabPreviewModel.Subject) -> Bool {
        switch subject {
        case .tab(let tab):
            browser.tabs.contains { $0.id == tab.id }
        case .folder(let folder, _):
            browser.folders.contains { $0.id == folder.id }
        case .split(_, let panes):
            panes.contains { pane in browser.tabs.contains { $0.id == pane.id } }
        }
    }
}

private struct TabPreviewCard: View {
    let subject: TabPreviewModel.Subject

    static let width: CGFloat = 252

    var body: some View {
        Group {
            switch subject {
            case .tab(let tab):
                TabFace(tab: tab)
            case .folder(let folder, let tabs):
                GroupFace(
                    symbol: "folder",
                    tint: folder.color.tint,
                    title: folder.name,
                    detail: tabs.count == 1
                        ? String(localized: "1 tab")
                        : String(localized: "\(tabs.count) tabs"),
                    tabs: tabs
                )
            case .split(let split, let panes):
                GroupFace(
                    symbol: "rectangle.split.2x1",
                    tint: Theme.accent,
                    title: String(localized: "Split"),
                    detail: split.axis == .stacked
                        ? String(localized: "Stacked")
                        : String(localized: "Side by side"),
                    tabs: panes
                )
            }
        }
        .frame(width: Self.width)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .glassSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }
}

private struct GroupFace: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let tabs: [BrowserTab]

    private static let listed = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)

                Text(verbatim: title)
                    .font(Theme.Font.rowTitle)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(verbatim: detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if !tabs.isEmpty {
                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(tabs.prefix(Self.listed)) { tab in
                        HStack(spacing: 6) {
                            TabFaviconMark(tab: tab)

                            Text(verbatim: tab.title)
                                .font(Theme.Font.label)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                    }

                    if tabs.count > Self.listed {
                        Text(verbatim: String(localized: "\(tabs.count - Self.listed) more"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private struct TabFaviconMark: View {
    let tab: BrowserTab

    var body: some View {
        Group {
            if let page = tab.internalPage {
                Image(systemName: page.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if SystemPages.showsStartFace(tab) {
                Image(systemName: SystemPages.startSymbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 12, height: 12)
    }
}

private struct TabFace: View {
    let tab: BrowserTab

    @State private var memoryBytes: UInt64?

    private static let imageHeight: CGFloat = 150

    private var isAsleep: Bool {
        TabIcon.isAsleep(tab.reclaimState)
    }

    private var host: String {
        guard !isSystemPage else { return "" }
        return URL(string: tab.urlString)?.host() ?? ""
    }

    private var isSystemPage: Bool {
        tab.internalPage != nil || tab.isShowingStartPage
    }

    private var memoryLabel: String? {
        guard !isSystemPage, let memoryBytes else { return nil }
        return Int64(memoryBytes).formatted(.byteCount(style: .memory))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let page = tab.internalPage {
                banner(symbol: page.symbol)
            } else if SystemPages.showsStartFace(tab) {
                banner(symbol: SystemPages.startSymbol)
            } else if let preview = tab.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: TabPreviewCard.width, height: Self.imageHeight, alignment: .top)
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
        .task(id: tab.id) {
            guard !isSystemPage else { return }
            while !Task.isCancelled {
                memoryBytes = WebProcessFootprint.bytes(of: tab.webView)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func banner(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: TabPreviewCard.width, height: 84)
            .background(Theme.Wash.hairline)
    }
}
