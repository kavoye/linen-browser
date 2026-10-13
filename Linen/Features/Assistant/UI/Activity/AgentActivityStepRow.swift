// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentActivityStepRow: View {
    let title: String
    let toolName: String?
    let detail: String?
    let links: [ConversationLog.ActivityLink]
    let state: ConversationLog.Step.State
    let inspection: AgentToolInspection?
    let connectsAbove: Bool
    let connectsBelow: Bool
    let tabID: UUID
    let browser: BrowserModel

    @State private var isExpanded = false

    private var canInspect: Bool {
        toolName != nil || !(detail?.isEmpty ?? true) || !links.isEmpty
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

                    if toolName != nil || !links.isEmpty {
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

                            if !links.isEmpty {
                                Text("\(links.count) links")
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
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                AgentStepInspection(
                    detail: detail,
                    links: links,
                    state: state,
                    inspection: inspection,
                    tabID: tabID,
                    browser: browser
                )
                .transition(.opacity)
            }
        }
        .padding(.leading, AgentActivityMetrics.railIndent)
        .padding(.top, 4)
        .padding(.bottom, connectsBelow ? 14 : 4)
        .overlay(alignment: .leading) {
            let dotRadius = AgentActivityMetrics.railDotDiameter / 2
            AgentBreadcrumbNode(
                connectsAbove: connectsAbove,
                connectsBelow: connectsBelow,
                state: breadcrumbState
            )
            .frame(width: AgentActivityMetrics.railWidth)
            .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - dotRadius }
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
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            if state == .running {
                Circle()
                    .fill(Theme.accent.opacity(0.22))
                    .frame(width: 13, height: 13)
                    .position(x: centerX, y: dotY)
            }

            Circle()
                .fill(dotColor)
                .frame(width: AgentActivityMetrics.railDotDiameter, height: AgentActivityMetrics.railDotDiameter)
                .position(x: centerX, y: dotY)
        }
        .allowsHitTesting(false)
    }
}

private struct AgentStepInspection: View {
    let detail: String?
    let links: [ConversationLog.ActivityLink]
    let state: ConversationLog.Step.State
    let inspection: AgentToolInspection?
    let tabID: UUID
    let browser: BrowserModel

    private var exchanges: [AgentAskedExchange]? {
        guard let detail, detail.contains(AgentQuestionModel.questionMark) else { return nil }
        return AgentAskedExchange.read(detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inspection {
                HStack(spacing: 5) {
                    Text("Status")
                        .foregroundStyle(.tertiary)
                    Text(statusLabel)
                        .foregroundStyle(.secondary)
                }
                .font(Theme.Font.caption)

                if let input = inspection.input {
                    inspectionText("Input", content: input, monospaced: true)
                }
                if let result = inspection.result {
                    inspectionText("Result", content: result, monospaced: false)
                }
                if inspection.imageCount > 0 {
                    Text("Images returned: \(inspection.imageCount)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }
            } else if detail == nil && links.isEmpty {
                Text("Details unavailable for this step.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }

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

    private var statusLabel: LocalizedStringResource {
        switch state {
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }

    private func inspectionText(_ title: LocalizedStringResource, content: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(verbatim: content)
                .font(monospaced ? .system(size: 11, design: .monospaced) : Theme.Font.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
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

struct AgentOutcomeChip: View {
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

struct AgentInlineButtonStyle: ButtonStyle {
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
