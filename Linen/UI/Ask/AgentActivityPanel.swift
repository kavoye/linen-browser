// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentActivityPanel: View {
    let traces: [ConversationLog.TaskTrace]
    let tabID: UUID
    let browser: BrowserModel
    let onRetry: (String) -> Void

    var body: some View {
        if traces.isEmpty {
            AgentActivityEmptyState()
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.traceGap) {
                    ForEach(traces.reversed()) { trace in
                        AgentTaskTraceView(
                            trace: trace,
                            tabID: tabID,
                            browser: browser,
                            onRetry: onRetry
                        )
                        .id(trace.id)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
            .onAppear { scrollToLatest(using: scrollProxy) }
            .onChange(of: traces.last?.id) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = traces.last?.id else { return }
        proxy.scrollTo(id, anchor: .top)
    }
}

private enum Metrics {
    static let gutter: CGFloat = 12
    static let cardInset: CGFloat = 10
    static let railIndent: CGFloat = 20
    static let titleIndent: CGFloat = 18
    static let railWidth: CGFloat = 12
    static let traceGap: CGFloat = 8

    static let answerWidth: CGFloat = 480
}

struct AgentStateMarker: View {
    let isRunning: Bool
    var tint: Color = Theme.accent

    var body: some View {
        Circle()
            .fill(isRunning ? tint : Color.secondary.opacity(0.5))
            .frame(width: 6, height: 6)
            .background {
                if isRunning {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 12, height: 12)
                }
            }
    }
}

struct AgentUsageSummary: View {
    let usage: ConversationLog.Usage

    private var cacheHitRate: Double? {
        guard usage.inputTokens > 0, usage.cachedTokens > 0 else { return nil }
        return Double(usage.cachedTokens) / Double(usage.inputTokens)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(usage.requestCount) req")
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text("\(usage.inputTokens.formatted(.number.notation(.compactName))) in")
            if let cacheHitRate {
                Text("(\(cacheHitRate.formatted(.percent.precision(.fractionLength(0)))) cached)")
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Text("\(usage.outputTokens.formatted(.number.notation(.compactName))) out")
        }
        .font(.system(size: 10, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct AgentActivityEmptyState: View {
    var body: some View {
        PanelNotice(
            symbol: "sparkle",
            title: "No tasks yet",
            caption: "Type @ in the address bar to start one on this page."
        )
    }
}

private struct AgentTaskTraceView: View {
    let trace: ConversationLog.TaskTrace
    let tabID: UUID
    let browser: BrowserModel
    let onRetry: (String) -> Void

    private var hasConclusion: Bool {
        !trace.response.isEmpty || trace.state == .cancelled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentTaskPrompt(
                prompt: trace.prompt,
                meta: metaLabel,
                connectsBelow: !trace.steps.isEmpty || hasConclusion
            )

            ForEach(trace.steps.enumerated(), id: \.element.id) { index, step in
                AgentActivityStepRow(
                    title: step.title,
                    toolName: step.toolName,
                    detail: step.detail,
                    links: step.links,
                    state: step.state,
                    connectsBelow: index < trace.steps.count - 1 || hasConclusion,
                    tabID: tabID,
                    browser: browser
                )
            }

            if hasConclusion {
                AgentTaskConclusion(
                    text: trace.response,
                    state: trace.state,
                    connectsAbove: !trace.steps.isEmpty,
                    onRetry: { onRetry(trace.prompt) }
                )
            }
        }
        .padding(.horizontal, Metrics.cardInset)
        .padding(.vertical, 8)
        .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(Theme.Wash.hairline, lineWidth: 1)
        }
    }

    private var metaLabel: String {
        var parts = [when]
        if let took {
            parts.append(took)
        }
        if !trace.steps.isEmpty {
            parts.append(String(localized: "\(trace.steps.count) steps"))
        }
        return parts.joined(separator: " · ")
    }

    private var when: String {
        guard trace.state != .running else { return String(localized: "now") }
        let age = Date().timeIntervalSince(trace.startedAt)
        guard age >= 45 else { return String(localized: "just now") }
        return trace.startedAt.formatted(.relative(presentation: .numeric))
    }

    private var took: String? {
        guard let finishedAt = trace.finishedAt else { return nil }
        let seconds = finishedAt.timeIntervalSince(trace.startedAt)
        guard seconds >= 0.05 else { return nil }
        let places = seconds < 10 ? 1 : 0
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: places))
        )
    }
}

private struct AgentTaskPrompt: View {
    let prompt: String
    let meta: String
    let connectsBelow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: prompt)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: meta)
                .font(.system(size: 10, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.leading, Metrics.railIndent)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            AgentBreadcrumbNode(
                connectsAbove: false,
                connectsBelow: connectsBelow,
                state: .accent
            )
            .frame(width: Metrics.railWidth)
        }
    }
}

private struct AgentActivityStepRow: View {
    let title: String
    let toolName: String?
    let detail: String?
    let links: [ConversationLog.ActivityLink]
    let state: ConversationLog.Step.State
    let connectsBelow: Bool
    let tabID: UUID
    let browser: BrowserModel

    @State private var isExpanded = false

    private var canInspect: Bool {
        !(detail?.isEmpty ?? true) || !links.isEmpty
    }

    private var inspectLabel: LocalizedStringResource {
        links.isEmpty ? "Inspect" : "\(links.count) links"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard canInspect else { return }
                withAnimation(Theme.Motion.quick) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: title)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer(minLength: 4)

                        if canInspect {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }

                    if toolName != nil || canInspect {
                        HStack(spacing: 6) {
                            if let toolName {
                                Text(verbatim: toolName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.Wash.hairline, in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
                            }

                            if canInspect {
                                Text(inspectLabel)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                AgentStepInspection(
                    detail: detail,
                    links: links,
                    tabID: tabID,
                    browser: browser
                )
                .transition(.opacity)
            }
        }
        .padding(.leading, Metrics.railIndent)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            AgentBreadcrumbNode(
                connectsAbove: true,
                connectsBelow: connectsBelow,
                state: breadcrumbState
            )
            .frame(width: Metrics.railWidth)
        }
    }

    private var breadcrumbState: AgentBreadcrumbNode.State {
        switch state {
        case .running:
            .running
        case .completed:
            .complete
        case .failed:
            .failed
        }
    }
}

private struct AgentBreadcrumbNode: View {
    enum State {
        case accent
        case running
        case complete
        case failed
        case stopped
    }

    let connectsAbove: Bool
    let connectsBelow: Bool
    let state: State

    private var dotColor: Color {
        switch state {
        case .accent, .running:
            Theme.accent
        case .complete:
            .secondary.opacity(0.62)
        case .failed:
            Theme.warning
        case .stopped:
            .secondary.opacity(0.45)
        }
    }

    private var lineColor: Color {
        state == .failed ? Theme.warning.opacity(0.7) : Theme.Wash.emphasis
    }

    private var lineWidth: CGFloat {
        state == .failed ? 2 : 1.5
    }

    var body: some View {
        GeometryReader { proxy in
            let centerX = proxy.size.width / 2
            let dotY = min(CGFloat(12), proxy.size.height / 2)

            Path { path in
                if connectsAbove {
                    path.move(to: CGPoint(x: centerX, y: 0))
                    path.addLine(to: CGPoint(x: centerX, y: max(0, dotY - 4)))
                }
                if connectsBelow {
                    path.move(to: CGPoint(x: centerX, y: dotY + 4))
                    path.addLine(to: CGPoint(x: centerX, y: proxy.size.height))
                }
            }
            .stroke(lineColor, lineWidth: lineWidth)

            if state == .running {
                Circle()
                    .fill(Theme.accent.opacity(0.22))
                    .frame(width: 13, height: 13)
                    .position(x: centerX, y: dotY)
            }

            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .position(x: centerX, y: dotY)
        }
        .allowsHitTesting(false)
    }
}

private struct AgentStepInspection: View {
    let detail: String?
    let links: [ConversationLog.ActivityLink]
    let tabID: UUID
    let browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }

            ForEach(links) { link in
                AgentActivityLinkRow(link: link, tabID: tabID, browser: browser)
            }
        }
    }
}

private struct AgentActivityLinkRow: View {
    let link: ConversationLog.ActivityLink
    let tabID: UUID
    let browser: BrowserModel

    var body: some View {
        Button {
            guard let tab = browser.tabs.first(where: { $0.id == tabID }) else { return }
            browser.activate(tab)
            tab.load(link.url)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: link.title)
                        .font(Theme.Font.control)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: link.url.absoluteString)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(Theme.Wash.hover, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this link in the task’s tab")
    }
}

private struct AgentTaskConclusion: View {
    let text: String
    let state: ConversationLog.TaskTrace.State
    let connectsAbove: Bool
    let onRetry: () -> Void

    private var isStreaming: Bool {
        state == .running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !text.isEmpty {
                Text(verbatim: isStreaming ? "\(text) ▍" : text)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: Metrics.answerWidth, alignment: .leading)
            }

            switch state {
            case .failed:
                HStack(spacing: 10) {
                    AgentOutcomeChip(label: "Failed", tint: Theme.warning)
                    Button("Try Again", action: onRetry)
                        .buttonStyle(AgentInlineButtonStyle())
                }
            case .cancelled:
                AgentOutcomeChip(label: "Stopped", tint: .secondary)
            case .running, .completed:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Metrics.railIndent)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            AgentBreadcrumbNode(
                connectsAbove: connectsAbove,
                connectsBelow: false,
                state: nodeState
            )
            .frame(width: Metrics.railWidth)
        }
    }

    private var nodeState: AgentBreadcrumbNode.State {
        switch state {
        case .running:
            .running
        case .failed:
            .failed
        case .cancelled:
            .stopped
        case .completed:
            .accent
        }
    }
}

private struct AgentOutcomeChip: View {
    let label: LocalizedStringResource
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.tight))
    }
}

private struct AgentInlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .strokeBorder(Theme.Wash.strong, lineWidth: 1)
                    .background(
                        Theme.accent.opacity(configuration.isPressed ? 0.12 : 0),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    )
            }
            .contentShape(Rectangle())
    }
}
