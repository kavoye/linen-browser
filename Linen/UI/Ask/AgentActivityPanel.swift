// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentActivityPanel: View {
    let traces: [ConversationLog.TaskTrace]
    let tabID: UUID
    let browser: BrowserModel
    let onRetry: (String) -> Void
    let onEdit: (String) -> Void
    let onSpeak: (String) -> Void

    var body: some View {
        if traces.isEmpty {
            AgentActivityEmptyState(browser: browser)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.traceGap) {
                    ForEach(Array(traces.enumerated()), id: \.element.id) { index, trace in
                        ChatTurnRule(label: Self.when(trace), isFirst: index == 0)

                        AgentTaskTraceView(
                            trace: trace,
                            tabID: tabID,
                            browser: browser,
                            onRetry: onRetry,
                            onEdit: onEdit,
                            onSpeak: onSpeak
                        )
                        .id(trace.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: AssistantChatMetrics.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                }
            }
            .onAppear { scrollToLatest(using: scrollProxy) }
            .onChange(of: traces.last?.id) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.response.count) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.steps.count) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.state) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
        }
    }

    private static let bottomAnchor = "chat.bottom"

    private static func when(_ trace: ConversationLog.TaskTrace) -> String {
        guard trace.state != .running else { return String(localized: "now") }
        let age = Date().timeIntervalSince(trace.startedAt)
        guard age >= 45 else { return String(localized: "just now") }
        return trace.startedAt.formatted(.relative(presentation: .numeric))
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard !traces.isEmpty else { return }
        Task {
            await Task.yield()
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }
}

enum AssistantChatMetrics {
    static let column: CGFloat = 680
    static let steps: CGFloat = 340
}

private enum Metrics {
    static let gutter: CGFloat = 12
    static let railIndent: CGFloat = 20
    static let railWidth: CGFloat = 12
    static let traceGap: CGFloat = 16
    static let turnGap: CGFloat = 7

    static let bubbleRadius: CGFloat = 13
    static let bubbleInset: CGFloat = 10
    static let bubbleGutter: CGFloat = 34
    static let action: CGFloat = 18
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
    let browser: BrowserModel

    private var pages: [AskContextPage] {
        AskContext.pages(browser: browser, mentionedTabIDs: [])
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Ask about this page")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("This chat reads the page it is open beside, and keeps its own thread per tab. Type @ to let it read another tab too.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !pages.isEmpty {
                ChipFlow(spacing: 6) {
                    ForEach(pages) { page in
                        AskPageChipView(
                            title: page.title,
                            host: page.host,
                            isAttached: page.isAttached,
                            fontSize: 10.5
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AgentTaskTraceView: View {
    let trace: ConversationLog.TaskTrace
    let tabID: UUID
    let browser: BrowserModel
    let onRetry: (String) -> Void
    let onEdit: (String) -> Void
    let onSpeak: (String) -> Void

    @State private var showsSteps: Bool?
    @State private var hovering = false

    private var stepsAreShown: Bool {
        showsSteps ?? (trace.state == .running)
    }

    private var isThinking: Bool {
        trace.state == .running && trace.response.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.turnGap) {
            ChatUserMessage(
                text: trace.prompt,
                showsActions: hovering,
                onEdit: { onEdit(trace.prompt) },
                onCopy: { copy(trace.prompt) },
                onRetry: { onRetry(trace.prompt) }
            )

            VStack(alignment: .leading, spacing: 5) {
                ChatAssistantMessage(
                    text: trace.response,
                    state: trace.state,
                    onRetry: { onRetry(trace.prompt) },
                    onOpenLink: open(_:)
                )

                ChatTurnFooter(
                    label: workLabel,
                    providerID: trace.providerID,
                    stepCount: trace.steps.count,
                    isThinking: isThinking,
                    stepsAreShown: stepsAreShown,
                    showsActions: hovering && !trace.response.isEmpty,
                    onToggleSteps: {
                        withAnimation(Theme.Motion.quick) { showsSteps = !stepsAreShown }
                    },
                    onCopy: { copy(trace.response) },
                    onSpeak: { onSpeak(trace.response) }
                )

                if stepsAreShown, !trace.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(trace.steps.enumerated(), id: \.element.id) { index, step in
                            AgentActivityStepRow(
                                title: step.title,
                                toolName: step.toolName,
                                detail: step.detail,
                                links: step.links,
                                state: step.state,
                                connectsAbove: index > 0,
                                connectsBelow: index < trace.steps.count - 1,
                                tabID: tabID,
                                browser: browser
                            )
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .frame(maxWidth: AssistantChatMetrics.steps, alignment: .leading)
                    .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .contextMenu {
            Button("Copy Answer") { copy(trace.response) }
                .disabled(trace.response.isEmpty)
            Button("Copy Question") { copy(trace.prompt) }
            Button("Ask Again") { onRetry(trace.prompt) }
            Button("Edit Question") { onEdit(trace.prompt) }
            Divider()
            Button("Speak Answer") { onSpeak(trace.response) }
                .disabled(trace.response.isEmpty)
        }
    }

    private func open(_ url: URL) {
        guard let tab = browser.tabs.first(where: { $0.id == tabID }) else { return }
        browser.activate(tab)
        tab.load(url)
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var workLabel: String {
        guard let took else {
            return trace.state == .running ? String(localized: "Working") : ""
        }
        return took
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

private struct ChatUserMessage: View {
    let text: String
    let showsActions: Bool
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.leading, Metrics.bubbleInset)
                .padding(.trailing, Metrics.bubbleInset + ChatBubble.tail)
                .padding(.top, 6)
                .padding(.bottom, 6 + ChatBubble.drop)
                .background {
                    ChatBubble()
                        .fill(.ultraThinMaterial)
                        .overlay { ChatBubble().fill(Theme.Wash.hairline) }
                }
                .padding(.leading, Metrics.bubbleGutter)

            HStack(spacing: 2) {
                if showsActions {
                    ChatAction(symbol: "doc.on.doc", help: "Copy this question", action: onCopy)
                    ChatAction(symbol: "arrow.clockwise", help: "Ask this again", action: onRetry)
                    ChatAction(symbol: "pencil", help: "Edit this question", action: onEdit)
                }
            }
            .frame(height: Metrics.action)
            .padding(.trailing, 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ChatBubble: Shape {
    static let tail: CGFloat = 4
    static let drop: CGFloat = 2.5

    private static let rise: CGFloat = 4
    private static let back: CGFloat = 5

    var radius: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.width - Self.tail, radius),
            height: max(rect.height - Self.drop, radius)
        )
        let r = min(radius, body.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + r),
            control: CGPoint(x: body.maxX, y: body.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - Self.rise))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX + Self.tail, y: body.maxY + Self.drop),
            control: CGPoint(x: body.maxX + Self.tail * 0.5, y: body.maxY + Self.drop * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.maxX - Self.back, y: body.maxY),
            control: CGPoint(x: body.maxX - Self.back * 0.2, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - r),
            control: CGPoint(x: body.minX, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: body.minX + r, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct ChatTurnRule: View {
    let label: String
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 8) {
            rule

            Text(verbatim: label)
                .font(Theme.Font.micro)
                .foregroundStyle(.tertiary)
                .fixedSize()

            rule
        }
        .padding(.vertical, isFirst ? 2 : 6)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: label))
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.Wash.hairline)
            .frame(height: 1)
    }
}

private struct ChatAssistantMessage: View {
    let text: String
    let state: ConversationLog.TaskTrace.State
    let onRetry: () -> Void
    let onOpenLink: (URL) -> Void

    private var isStreaming: Bool {
        state == .running
    }

    /// Selectable text is an AppKit text view; one per chunk of a streaming
    /// answer costs more than the answer does.
    @ViewBuilder private var answer: some View {
        if isStreaming {
            Text(verbatim: text)
                .font(.system(size: 13))
                .lineSpacing(2)
        } else {
            ChatMarkdown(text: text, onOpenLink: onOpenLink)
                .textSelection(.enabled)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !text.isEmpty {
                answer
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
        .padding(.trailing, Metrics.bubbleGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatTurnFooter: View {
    let label: String
    let providerID: String?
    let stepCount: Int
    let isThinking: Bool
    let stepsAreShown: Bool
    let showsActions: Bool
    let onToggleSteps: () -> Void
    let onCopy: () -> Void
    let onSpeak: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 5) {
                if isThinking {
                    TypingDots()
                        .frame(width: Metrics.action, height: Metrics.action)
                } else if let providerID {
                    ProviderBrandIcon(providerID: providerID, size: 12)
                        .frame(width: Metrics.action, height: Metrics.action)
                }

                if !label.isEmpty {
                    Text(verbatim: label)
                        .font(Theme.Font.caption)
                        .monospacedDigit()
                }

                if stepCount > 0 {
                    StepsToggle(count: stepCount, isShown: stepsAreShown, action: onToggleSteps)
                }
            }
            .foregroundStyle(.tertiary)
            .padding(.trailing, 4)

            if showsActions {
                ChatAction(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy this answer") {
                    onCopy()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                }
                ChatAction(symbol: "speaker.wave.2", help: "Read this answer aloud", action: onSpeak)
            }

            Spacer(minLength: 0)
        }
        .frame(height: Metrics.action)
        .padding(.trailing, Metrics.bubbleGutter)
    }
}

private struct StepsToggle: View {
    let count: Int
    let isShown: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(verbatim: "·")
                Text("\(count) steps")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(isShown ? 0 : -90))
            }
            .foregroundStyle(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(isShown ? Text("Hide the steps") : Text("Show the steps"))
    }
}

private struct ChatAction: View {
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .imageScale(.small)
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: Metrics.action, height: Metrics.action)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(help))
    }
}

private struct TypingDots: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 3.5, height: 3.5)
                    .opacity(pulsing ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever().delay(Double(index) * 0.18),
                        value: pulsing
                    )
            }
        }
        .onAppear { pulsing = true }
        .accessibilityHidden(true)
    }
}

private struct AgentActivityStepRow: View {
    let title: String
    let toolName: String?
    let detail: String?
    let links: [ConversationLog.ActivityLink]
    let state: ConversationLog.Step.State
    let connectsAbove: Bool
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
                    HStack(spacing: 5) {
                        Text(verbatim: title)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if canInspect {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }

                        Spacer(minLength: 0)
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
                                    .background(Theme.Wash.hairline, in: RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous))
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
                connectsAbove: connectsAbove,
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

    private var exchanges: [AgentAskedExchange]? {
        guard let detail, detail.contains(AgentQuestionModel.questionMark) else { return nil }
        return AgentAskedExchange.read(detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let exchanges {
                AgentAskedList(exchanges: exchanges)
            } else if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
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
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Wash.hover, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open this link in the task’s tab")
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
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.tight, style: .continuous))
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
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.Wash.strong, lineWidth: 1)
                    .background(
                        Theme.accent.opacity(configuration.isPressed ? 0.12 : 0),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    )
            }
            .contentShape(Rectangle())
    }
}
