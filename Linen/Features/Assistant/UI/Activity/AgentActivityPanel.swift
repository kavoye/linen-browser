// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentActivityPanel: View {
    let traces: [ConversationLog.TaskTrace]
    let tabID: UUID
    let browser: BrowserModel
    var isCompacting = false
    var compactionMessage: LocalizedStringResource?
    let onRetry: (ConversationLog.TaskTrace) -> Void
    let onEdit: (ConversationLog.TaskTrace) -> Void
    var speakingAnswerID: UUID?
    var readsWithOpenAI = false
    let onSpeak: (ConversationLog.TaskTrace) -> Void

    @State private var edges = Edges()

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
                VStack(alignment: .leading, spacing: AgentActivityMetrics.traceGap) {
                    ForEach(traces) { trace in
                        AgentTaskTraceView(
                            trace: trace,
                            tabID: tabID,
                            browser: browser,
                            onRetry: onRetry,
                            onEdit: onEdit,
                            isSpeaking: trace.id == speakingAnswerID,
                            readsWithOpenAI: readsWithOpenAI,
                            onSpeak: onSpeak,
                            isLatest: trace.id == traces.last?.id
                        )
                        .id(trace.id)
                    }

                    if isCompacting {
                        HStack(spacing: 8) {
                            Spinner(size: 13)
                            Text("Compacting context…")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    } else if let compactionMessage {
                        Text(compactionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, AgentActivityMetrics.gutter)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: AssistantChatMetrics.column, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
            .onScrollGeometryChange(for: Edges.self) { geometry in
                let top = geometry.contentOffset.y + geometry.contentInsets.top
                let bottom = geometry.contentSize.height - geometry.contentOffset.y
                    - geometry.containerSize.height + geometry.contentInsets.bottom
                return Edges(hasContentAbove: top > 1, hasContentBelow: bottom > 1)
            } action: { _, edges in
                self.edges = edges
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: edges.hasContentAbove ? 12 : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: edges.hasContentBelow ? 10 : 0)
                }
            }
            .onAppear { scrollToLatest(using: scrollProxy) }
            .onChange(of: traces.last?.id) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.response.count) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.progressUpdates.count) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.steps.count) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: traces.last?.state) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
            .onChange(of: isCompacting) { _, _ in
                scrollToLatest(using: scrollProxy)
            }
        }
    }

    private static let bottomAnchor = "chat.bottom"

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

enum AgentActivityMetrics {
    static let gutter: CGFloat = 12
    static let railIndent: CGFloat = railWidth / 2 + 5
    static let railWidth: CGFloat = action
    static let railDotDiameter: CGFloat = 6
    static let traceGap: CGFloat = 16
    static let turnGap: CGFloat = 7

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

private struct Edges: Equatable {
    var hasContentAbove = false
    var hasContentBelow = false
}

private struct AgentActivityEmptyState: View {
    let browser: BrowserModel

    private var siteName: String? {
        guard let tab = browser.activeTab, tab.isShowingRealPage,
              let host = URL(string: tab.urlString)?.displayHost
        else { return nil }
        return SiteName.title(forHost: host)
    }

    var body: some View {
        VStack(spacing: 9) {
            ComposingOrb(size: 34, isAnimating: false)
                .frame(width: 26, height: 26)
                .opacity(0.5)

            Group {
                if let siteName {
                    Text("Ask about the \(siteName) page")
                } else {
                    Text("Ask about this page")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text("Each tab has a separate chat with access to its page. Type @ to include another tab.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
