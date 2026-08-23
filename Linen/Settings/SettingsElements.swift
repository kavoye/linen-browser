// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OptionList<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: LocalizedStringResource
        var caption: LocalizedStringResource?

        var id: Value {
            value
        }
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    private var selectionBinding: Binding<Value> {
        Binding(get: { selection }, set: { onSelect($0) })
    }

    var body: some View {
        Picker(selection: selectionBinding) {
            ForEach(options) { option in
                OptionPickerLabel(label: option.label, caption: option.caption)
                    .tag(option.value)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.radioGroup)
        .controlSize(.small)
        .padding(.horizontal, SettingsMetrics.pickerHorizontalInset)
        .padding(.vertical, SettingsMetrics.pickerVerticalInset)
    }
}

private struct OptionPickerLabel: View {
    let label: LocalizedStringResource
    let caption: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Font.rowTitle)

            if let caption {
                Text(caption)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsMetrics.pickerItemPaddingV)
    }
}

struct SiteIcon: View {
    let host: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let favicon = FaviconLoader.shared.cached(for: host) {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous)
                    .fill(.clear)
                    .settingsSurface(
                        in: RoundedRectangle(
                            cornerRadius: Theme.Radius.tight,
                            style: .continuous
                        )
                    )
                    .overlay {
                        Image(systemName: "globe")
                            .font(.system(size: size * 0.62))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct SiteRow<Trailing: View>: View {
    let host: String
    var summary: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(host: host)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: host)
                    .font(Theme.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let summary, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, 9)
    }
}

struct DrillInRow: View {
    let title: LocalizedStringResource
    var symbol: String?
    var tint: Color = .secondary
    var detail: LocalizedStringResource?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tint)
                        }
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(Theme.Font.rowTitle)

                Spacer(minLength: 8)

                if let detail {
                    Text(detail)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .settingsRowHover(isActive: hovering, tint: tint)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

struct AddRow: View {
    let title: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 26 * 0.32, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                    )
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)

                Text(title)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 9)
            .settingsRowHover(isActive: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

struct SubPageHeader: View {
    private let button: SettingsButton

    init(backTitle: LocalizedStringResource, onBack: @escaping () -> Void) {
        button = SettingsButton(title: backTitle, symbol: "chevron.left", action: onBack)
    }

    init(verbatimBackTitle: String, onBack: @escaping () -> Void) {
        button = SettingsButton(
            verbatimTitle: verbatimBackTitle,
            symbol: "chevron.left",
            action: onBack
        )
    }

    var body: some View {
        button
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsEmptyState: View {
    let symbol: String
    let title: LocalizedStringResource
    var caption: LocalizedStringResource?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.Font.rowTitle)
                .foregroundStyle(.secondary)

            if let caption {
                Text(caption)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

struct StatusRow<Trailing: View>: View {
    let tint: Color
    let symbol: String
    let title: LocalizedStringResource
    var caption: LocalizedStringResource?
    var verbatimCaption: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.rowTitle)

                if let verbatimCaption {
                    Text(verbatim: verbatimCaption)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                } else if let caption {
                    Text(caption)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, SettingsMetrics.rowPaddingV)
    }
}

struct SectionActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            content
        }
        .padding(.top, 8)
    }
}

struct StatStrip: View {
    struct Figure: Identifiable {
        let value: String
        let label: LocalizedStringResource

        var id: String {
            value + String(localized: label)
        }
    }

    let figures: [Figure]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: figure.value)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.identity)

                    Text(figure.label)
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 12)
    }
}

struct ChipList: View {
    let items: [LocalizedStringResource]

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(Theme.Font.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .settingsSurface(
                        in: RoundedRectangle(
                            cornerRadius: Theme.Radius.chip,
                            style: .continuous
                        )
                    )
            }
        }
        .padding(.vertical, 13)
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(of: subviews, within: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if next > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
