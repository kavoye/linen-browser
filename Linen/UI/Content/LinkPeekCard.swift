// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct LinkPeekOverlay: View {
    let peek: LinkPeek
    let tabID: UUID

    @State private var cardSize: CGSize = .zero

    private static let gap: CGFloat = 18
    private static let margin: CGFloat = 12
    private static let pointerInset: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            if let shown = peek.shown, shown.tabID == tabID {
                LinkPeekCard(shown: shown)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                    .offset(
                        x: horizontal(for: shown.anchor, in: proxy.size),
                        y: vertical(for: shown.anchor, in: proxy.size)
                    )
                    .opacity(cardSize == .zero ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func horizontal(for anchor: CGPoint, in size: CGSize) -> CGFloat {
        let ideal = anchor.x - Self.pointerInset
        let limit = max(size.width - cardSize.width - Self.margin, Self.margin)
        return min(max(ideal, Self.margin), limit)
    }

    private func vertical(for anchor: CGPoint, in size: CGSize) -> CGFloat {
        let below = anchor.y + Self.gap
        if below + cardSize.height + Self.margin <= size.height {
            return below
        }
        let above = anchor.y - Self.gap - cardSize.height
        if above >= Self.margin {
            return above
        }
        return max(size.height - cardSize.height - Self.margin, Self.margin)
    }
}

private struct LinkPeekCard: View {
    let shown: LinkPeek.Shown

    static let width: CGFloat = 328
    private static let imageHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = shown.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width, height: Self.imageHeight, alignment: .top)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 9) {
                body(for: shown.phase)
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .frame(width: Self.width)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .glassSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    @ViewBuilder
    private func body(for phase: LinkPeek.Phase) -> some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading this page…")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 34, alignment: .leading)

        case .ready(let summary):
            VStack(alignment: .leading, spacing: 9) {
                if !summary.gist.isEmpty {
                    Text(verbatim: summary.gist)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !summary.points.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(summary.points.enumerated()), id: \.offset) { _, point in
                            PointRow(point: point)
                        }
                    }
                }
            }

        case .stillLoading:
            Text("This page is still loading.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 34, alignment: .leading)

        case .mediaOnly:
            Text("Only images and video on this page.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 34, alignment: .leading)

        case .noText:
            Text("This page has no text to summarize.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 34, alignment: .leading)

        case .failed:
            Text("Couldn’t summarize this page.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 34, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text(verbatim: shown.host)
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if case .ready = shown.phase {
                Text(verbatim: "·")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)

                Text("AI summary, can be wrong")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PointRow: View {
    let point: LinkPeekSummary.Point

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(.tertiary)
                .frame(width: 3, height: 3)
                .offset(y: -3)

            Text(line)
                .font(Theme.Font.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var line: AttributedString {
        var detail = AttributedString(point.detail)
        detail.foregroundColor = .secondary
        guard !point.label.isEmpty else { return detail }

        var label = AttributedString(point.label + " ")
        label.font = Theme.Font.secondary.weight(.semibold)
        label.foregroundColor = .primary
        return label + detail
    }
}
