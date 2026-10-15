// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AssistantContextIndicator: View {
    let tokens: Int
    let breakdown: ContextBreakdown?
    let window: ContextWindow.Resolution
    let providerNotice: String?
    let canCompact: Bool
    let canClear: Bool
    let isCompacting: Bool
    let compactionMessage: LocalizedStringResource?
    let onCompact: () -> Void
    let onClear: () -> Void

    @State private var isPresenting = false
    @State private var isHovering = false
    @State private var isHoveringPopover = false
    @State private var isPinned = false

    private var hasKnownLimit: Bool {
        window.source != .fallback
    }

    private var fraction: Double {
        hasKnownLimit ? min(1, max(0, Double(tokens) / Double(max(1, window.tokens)))) : 0
    }

    private var isOverLimit: Bool {
        hasKnownLimit && tokens > window.tokens
    }

    private var overage: String {
        compact(tokens - window.tokens)
    }

    private var percent: Int {
        Int((fraction * 100).rounded())
    }

    private var usedShare: String {
        Self.percentShare(percent)
    }

    private var leftShare: String {
        Self.percentShare(100 - percent)
    }

    private static func percentShare(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        Button {
            isPinned = true
            isPresenting = true
        } label: {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.13), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(isOverLimit ? Color.red : fraction >= 0.9 ? Color.orange : Color.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.Motion.settle, value: fraction)
                    .animation(Theme.Motion.settle, value: isOverLimit)
            }
            .frame(width: 13, height: 13)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context window")
        .accessibilityValue(isOverLimit
            ? Text("Estimated: over the limit by \(overage) tokens")
            : hasKnownLimit
            ? Text("Estimated: \(usedShare) used, \(leftShare) left")
            : Text("Estimated: \(tokens) tokens. Model limit unavailable."))
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            guard isHovering else { return }
            do {
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
                isPresenting = true
            } catch {   }
        }
        .task(id: isHovering || isHoveringPopover || isPinned) {
            guard !isHovering, !isHoveringPopover, !isPinned else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                isPresenting = false
            } catch {   }
        }
        .onChange(of: isPresenting) { _, showing in
            if !showing {
                isPinned = false
                isHoveringPopover = false
            }
        }
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context window")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Group {
                            if isOverLimit {
                                Text("Over the limit by \(overage) tokens")
                                    .foregroundStyle(.red)
                            } else if hasKnownLimit {
                                Text("\(usedShare) used")
                            } else {
                                Text("\(compact(tokens)) tokens used")
                            }
                        }
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                        Spacer(minLength: 12)
                        if hasKnownLimit {
                            Text(verbatim: "\(compact(tokens)) / \(compact(window.tokens))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    if let providerNotice {
                        Text(verbatim: providerNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ContextUsageBar(segments: barSegments)
                if !rows.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(rows) { row in
                            ContextUsageRow(row: row)
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                }
                if !hasKnownLimit {
                    Text("Model limit unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasUsage {
                    Divider()
                    HStack {
                        Group {
                            if let compactionMessage {
                                Text(compactionMessage)
                            } else {
                                Text(window.source == .configured ? "Estimated usage · custom limit" : "Estimated usage")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.opacity)
                        Spacer(minLength: 8)
                        Button {
                            isPresenting = false
                            onClear()
                        } label: {
                            Text(LocalizedStringResource("context.clear", defaultValue: "Clear…"))
                        }
                        .disabled(!canClear || isCompacting)
                        .help("Start fresh in this chat.")
                        Button {
                            isPinned = true
                            onCompact()
                        } label: {
                            ZStack {
                                if isCompacting {
                                    Spinner(size: 11)
                                }
                                Text("Compact")
                                    .opacity(isCompacting ? 0 : 1)
                            }
                        }
                        .accessibilityLabel(isCompacting ? Text("Compacting…") : Text("Compact"))
                        .disabled(!canCompact || isCompacting)
                        .help("Summarize older context now. Context also compacts automatically when needed.")
                    }
                }
            }
            .font(.callout)
            .animation(Theme.Motion.settle, value: tokens)
            .animation(Theme.Motion.settle, value: window.tokens)
            .animation(Theme.Motion.settle, value: breakdown)
            .animation(Theme.Motion.quick, value: isCompacting)
            .animation(Theme.Motion.settle, value: hasUsage)
            .frame(width: 280)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .onHover { isHoveringPopover = $0 }
            .chromePopoverAppearance()
        }
    }

    private var hasUsage: Bool {
        tokens > 0 || isCompacting || compactionMessage != nil
    }

    private var usedRows: [ContextUsageRow.Model] {
        guard let breakdown, !breakdown.scaled(to: tokens).isEmpty else {
            return tokens > 0 ? [.init(kind: .used, tokens: tokens)] : []
        }
        return breakdown.scaled(to: tokens).map { .init(kind: .category($0.category), tokens: $0.tokens) }
    }

    private var reservedTokens: Int {
        guard hasKnownLimit, let breakdown else { return 0 }
        return min(breakdown.reservedTokens, max(0, window.tokens - tokens))
    }

    private var rows: [ContextUsageRow.Model] {
        var rows = usedRows
        if reservedTokens > 0 {
            rows.append(.init(kind: .reserved, tokens: reservedTokens))
        }
        if hasKnownLimit, tokens > 0 {
            rows.append(.init(kind: .free, tokens: max(0, window.tokens - tokens - reservedTokens)))
        }
        let shares = Self.tenthsOfAPercent(rows.map(\.tokens))
        return zip(rows, shares).map { row, tenths in
            var row = row
            row.share = (Double(tenths) / 1_000).formatted(.percent.precision(.fractionLength(1)))
            row.label = compact(row.tokens)
            return row
        }
    }

    private static func tenthsOfAPercent(_ values: [Int]) -> [Int] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in 0 } }
        let exact = values.map { Double($0) * 1_000 / Double(total) }
        var tenths = exact.map { Int($0) }
        let order = exact.indices.sorted { exact[$0] - Double(tenths[$0]) > exact[$1] - Double(tenths[$1]) }
        for index in order.prefix(1_000 - tenths.reduce(0, +)) {
            tenths[index] += 1
        }
        return tenths
    }

    private var barSegments: [ContextUsageBar.Segment] {
        if isOverLimit {
            return [.init(id: "over", fraction: 1, style: .over)]
        }
        let denominator = Double(max(1, hasKnownLimit ? window.tokens : tokens))
        var segments = usedRows.map {
            ContextUsageBar.Segment(id: $0.id, fraction: Double($0.tokens) / denominator, style: .fill($0.kind.color))
        }
        if reservedTokens > 0 {
            segments.append(.init(id: "reserved", fraction: Double(reservedTokens) / denominator, style: .reserved))
        }
        return segments
    }

    private func compact(_ value: Int) -> String {
        max(0, value).formatted(.number.notation(.compactName).precision(.fractionLength(0...(value >= 1_000_000 ? 2 : 1))))
    }
}

private struct ContextUsageBar: View {
    enum Style {
        case fill(Color), reserved, over
    }

    struct Segment: Identifiable {
        let id: String
        let fraction: Double
        let style: Style
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    fill(segment.style)
                        .frame(width: max(2, proxy.size.width * min(1, segment.fraction)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(Theme.Wash.selection)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fill(_ style: Style) -> some View {
        switch style {
        case .fill(let color):
            Rectangle().fill(color)
        case .reserved:
            Rectangle().fill(Theme.Wash.emphasis)
        case .over:
            Rectangle().fill(.red)
        }
    }
}

private struct ContextUsageRow: View {
    enum Kind: Hashable {
        case category(ContextBreakdown.Category), used, reserved, free

        var title: LocalizedStringResource {
            switch self {
            case .category(.messages):
                "Messages"
            case .category(.toolActivity):
                "Tool activity"
            case .category(.availableTools):
                "Available tools"
            case .category(.instructions):
                "Instructions"
            case .category(.reasoning):
                "Reasoning"
            case .category(.images):
                "Images"
            case .used:
                "Used"
            case .reserved:
                "Reserved for reply"
            case .free:
                "Free space"
            }
        }

        var detail: LocalizedStringResource {
            switch self {
            case .category(.messages):
                "Your prompts and the assistant’s replies."
            case .category(.toolActivity):
                "Actions the assistant took and the page content they returned."
            case .category(.availableTools):
                "Descriptions of the tools the assistant can use, sent with every request."
            case .category(.instructions):
                "Guidance Linen sends to the model with every request."
            case .category(.reasoning):
                "The model’s thinking before it answers."
            case .category(.images):
                "Images attached to the conversation."
            case .used:
                "Context this conversation uses."
            case .reserved:
                "Space kept free for the model’s answer."
            case .free:
                "Space still available for this conversation."
            }
        }

        var color: Color {
            switch self {
            case .category(.messages):
                .blue
            case .category(.toolActivity):
                .orange
            case .category(.availableTools):
                .green
            case .category(.instructions):
                .yellow
            case .category(.reasoning):
                .purple
            case .category(.images):
                .pink
            case .used:
                .secondary
            case .reserved:
                Theme.Wash.emphasis
            case .free:
                Theme.Wash.selection
            }
        }
    }

    struct Model: Identifiable {
        let kind: Kind
        let tokens: Int
        var label = ""
        var share = ""

        var id: String {
            String(describing: kind)
        }
    }

    let row: Model

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(row.kind.color)
                .frame(width: 9, height: 9)
            Text(row.kind.title)
                .foregroundStyle(row.kind == .free || row.kind == .reserved ? .secondary : .primary)
                .lineLimit(1)
                .help(Text(row.kind.detail))
            Spacer(minLength: 8)
            Text(verbatim: row.label)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
            Text(verbatim: row.share)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .frame(minWidth: 54, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
