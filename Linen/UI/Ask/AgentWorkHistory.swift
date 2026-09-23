// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentWorkHistory: View {
    let trace: ConversationLog.TaskTrace
    let tabID: UUID
    let browser: BrowserModel
    let showsDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let inspections = showsDetails ? AgentToolInspection.forTrace(trace) : [:]
            let visibleIndices = trace.steps.indices.filter { trace.steps[$0].isVisibleInChat }
            if showsDetails,
               let summaries = trace.checkpoint?.openAI?.presentation?.summaries, !summaries.isEmpty {
                AgentReasoningSummary(summaries: summaries)
            }
            ForEach(0...trace.steps.count, id: \.self) { index in
                ForEach(trace.progressUpdates.filter { $0.afterStepCount == index }) { update in
                    Text(verbatim: update.text)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                }
                if index == trace.steps.count, trace.state == .running, let liveProgress = trace.liveProgress {
                    Text(verbatim: liveProgress)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                }
                if showsDetails, index < trace.steps.count, trace.steps[index].isVisibleInChat {
                    let step = trace.steps[index]
                    let previous = visibleIndices.last { $0 < index }
                    let next = visibleIndices.first { $0 > index }
                    AgentActivityStepRow(
                        title: step.title, toolName: step.toolName,
                        detail: step.detail, links: step.links, state: step.state,
                        inspection: inspections[step.id],
                        connectsAbove: previous.map { prior in
                            !trace.progressUpdates.contains { $0.afterStepCount > prior && $0.afterStepCount <= index }
                        } ?? false,
                        connectsBelow: next.map { following in
                            !trace.progressUpdates.contains { $0.afterStepCount > index && $0.afterStepCount <= following }
                        } ?? false,
                        tabID: tabID, browser: browser
                    )
                    .frame(maxWidth: AssistantChatMetrics.steps, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AgentReasoningSummary: View {
    let summaries: [String]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Theme.Motion.quick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text("Reasoning summary")
                        .font(Theme.Font.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                Text(verbatim: summaries.joined(separator: "\n\n"))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.Wash.strong)
                            .frame(width: 2)
                    }
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
