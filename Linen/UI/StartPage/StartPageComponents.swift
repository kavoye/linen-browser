// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

private struct StartPageSurface<S: Shape>: ViewModifier {
    let isHovering: Bool
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    private var onLight: Bool {
        colorScheme == .light
    }

    private var baseFill: Color {
        ChromeInk.wash(onLight: onLight, opacity: onLight ? 0.025 : 0.04)
    }

    private var hoverFill: AnyShapeStyle {
        isHovering ? ChromeInk.hoverStyle : AnyShapeStyle(.clear)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(baseFill)
                    .overlay { shape.fill(hoverFill) }
            }
            .contentShape(shape)
    }
}

extension View {
    func startPageSurface<S: Shape>(
        isHovering: Bool = false,
        in shape: S
    ) -> some View {
        modifier(StartPageSurface(isHovering: isHovering, shape: shape))
    }
}

struct LiveWaveform: View {
    let isListening: Bool

    private static let profile: [Double] = [0.30, 0.55, 0.88, 0.62, 1.0, 0.50, 0.76, 0.34]
    private static let height: Double = 40

    var body: some View {
        Group {
            if isListening {
                TimelineView(.animation) { context in
                    bars(
                        level: MicLevel.shared.level,
                        phase: context.date.timeIntervalSinceReferenceDate
                    )
                }
            } else {
                bars(level: 0, phase: 0)
            }
        }
        .frame(height: Self.height)
    }

    private func bars(level: Double, phase: TimeInterval) -> some View {
        HStack(spacing: 4) {
            ForEach(Self.profile.enumerated(), id: \.offset) { index, weight in
                Capsule()
                    .fill(isListening ? .red : Theme.chrome(0.26 + weight * 0.34))
                    .frame(
                        width: 4,
                        height: barHeight(
                            weight: weight,
                            index: index,
                            level: level,
                            phase: phase
                        )
                    )
            }
        }
    }

    private func barHeight(
        weight: Double,
        index: Int,
        level: Double,
        phase: TimeInterval
    ) -> Double {
        guard isListening else { return max(4, Self.height * weight * 0.62) }
        let travel = 0.55 + 0.45 * sin(phase * 6 + Double(index) * 0.9)
        return max(4, Self.height * (0.14 + level * weight * travel))
    }
}

struct StartPageTaskCard: View {
    let trace: ConversationLog.TaskTrace
    let action: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    private static let promptHeight: CGFloat = 34

    private var prompt: String {
        let trimmed = trace.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.reversed().drop { $0 == "." }.reversed())
    }

    private var showsRemove: Bool {
        hovering && trace.state != .running
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: prompt)
                    .font(Theme.Font.row)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 16)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: Self.promptHeight,
                        alignment: .topLeading
                    )

                ZStack(alignment: .leading) {
                    StartPageTaskProvenance(
                        state: trace.state,
                        startedAt: trace.startedAt
                    )
                    .opacity(hovering ? 0 : 1)

                    Label("Ask Again", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0)
                }
                .font(Theme.Font.caption)
                .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .startPageSurface(
                isHovering: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            CloseButton(help: String(localized: "Remove Task"), action: onRemove)
                .padding(4)
                .opacity(showsRemove ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help("Ask again: \(prompt)")
    }
}

private struct StartPageTaskProvenance: View {
    let state: ConversationLog.TaskTrace.State
    let startedAt: Date

    private var status: (label: LocalizedStringResource, color: Color)? {
        switch state {
        case .completed:
            nil
        case .running:
            ("Running", Theme.accent)
        case .failed:
            ("Failed", Theme.warning)
        case .cancelled:
            ("Stopped", .secondary)
        }
    }

    private var timestamp: String {
        guard state != .running else { return String(localized: "now") }
        guard Date().timeIntervalSince(startedAt) >= 45 else {
            return String(localized: "just now")
        }
        return startedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    var body: some View {
        HStack(spacing: 5) {
            if let status {
                Circle()
                    .fill(status.color)
                    .frame(width: 5, height: 5)
                Text(status.label)
                    .foregroundStyle(.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(.quaternary)
            }
            Text(verbatim: timestamp)
                .foregroundStyle(.tertiary)
        }
    }
}

struct StartPageSiteTile: View {
    let site: StartPageSite
    let action: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RemoteSiteBadge(host: site.host, size: 26)
                Text(verbatim: site.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(site.visits) visits")
                    .font(Theme.Font.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .startPageSurface(
                isHovering: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(verbatim: site.url))
        .overlay(alignment: .topTrailing) {
            CloseButton(help: String(localized: "Remove \(site.title)"), action: onRemove)
                .padding(3)
                .opacity(hovering ? 1 : 0)
        }
        .onHover { hovering = $0 }
    }
}

struct StartPageDownloadRow: View {
    let item: DownloadManager.Item
    let downloads: DownloadManager

    @State private var hovering = false

    private var showsRemove: Bool {
        hovering && !item.isRunning
    }

    var body: some View {
        Button {
            guard item.state == .finished else { return }
            downloads.open(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.isRunning ? "arrow.down" : "doc")
                    .font(Theme.Font.body)
                    .foregroundStyle(
                        item.state == .finished
                            ? AnyShapeStyle(Theme.accent)
                            : AnyShapeStyle(.secondary)
                    )
                    .frame(width: 15)

                Text(verbatim: item.filename)
                    .font(Theme.Font.row)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if item.isRunning, let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                        .frame(width: 70)
                } else {
                    Text(verbatim: item.sizeSummary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .fixedSize()
                        .opacity(showsRemove ? 0 : 1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .hoverBackground(
                isActive: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if !item.isRunning {
                CloseButton(help: String(localized: "Remove from List")) {
                    downloads.remove(item)
                }
                .padding(.trailing, 7)
                .opacity(showsRemove ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
    }
}

struct HistoryRow: View {
    let entry: HistoryStore.Entry
    let action: () -> Void
    var onRemove: (() -> Void)?
    var onOpenInNewTab: ((_ activate: Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    @State private var hovering = false

    private var showsRemove: Bool {
        hovering && onRemove != nil
    }
    private var host: String {
        URL(string: entry.url)?.displayHost ?? entry.url
    }
    private var stamp: String {
        entry.date.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                RemoteSiteBadge(host: host, size: 15)
                Text(verbatim: entry.title)
                    .font(Theme.Font.row)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(verbatim: host)
                    .font(Theme.Font.label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: stamp)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .fixedSize()
                    .opacity(showsRemove ? 0 : 1)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .hoverBackground(
                isActive: hovering,
                in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: entry.url))
        .onMiddleClick { onOpenInNewTab?(false) }
        .contextMenu {
            if let onOpenInNewTab {
                Button("Open in New Tab") { onOpenInNewTab(false) }
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            if let onRemove {
                Button("Remove from History", role: .destructive, action: onRemove)
            }
        }
        .overlay(alignment: .trailing) {
            if let onRemove {
                CloseButton(help: String(localized: "Remove from History"), action: onRemove)
                    .padding(.trailing, 7)
                    .opacity(showsRemove ? 1 : 0)
            }
        }
        .onHover {
            hovering = $0
            onHoverChanged?($0)
        }
    }

    private func open() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if let onOpenInNewTab, flags.contains(.command) {
            onOpenInNewTab(flags.contains(.shift))
        } else {
            action()
        }
    }
}

struct StartPageShowAllButton: View {
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Show All")
                    .font(Theme.Font.control)
                if count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(y: hovering ? -1 : 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .startPageSurface(isHovering: hovering, in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}

struct SuggestionChip: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(Theme.Font.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .startPageSurface(isHovering: hovering, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
    }
}
