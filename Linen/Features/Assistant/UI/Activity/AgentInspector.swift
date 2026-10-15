// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@MainActor
@Observable
final class AgentAttention {
    private enum Key {
        static let seen = "agent.seenFailures"
    }

    private(set) var seenFailures: [UUID: Int] = [:]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Key.seen) as? [String: Int] ?? [:]
        seenFailures = stored.reduce(into: [:]) { found, entry in
            guard let anchorID = UUID(uuidString: entry.key) else { return }
            found[anchorID] = entry.value
        }
    }

    func review(_ count: Int, inAnchor anchorID: UUID?, isShowing: Bool) {
        guard isShowing, let anchorID else { return }
        let seen = max(seenFailures[anchorID] ?? 0, count)
        guard seenFailures[anchorID] != seen else { return }
        seenFailures[anchorID] = seen
        persist()
    }

    func needsAttention(failureCount: Int, inAnchor anchorID: UUID?, isShowing: Bool) -> Bool {
        guard !isShowing, let anchorID else { return false }
        return failureCount > (seenFailures[anchorID] ?? 0)
    }

    func retainAnchors(_ anchorIDs: Set<UUID>) {
        let kept = seenFailures.filter { anchorIDs.contains($0.key) }
        guard kept.count != seenFailures.count else { return }
        seenFailures = kept
        persist()
    }

    private func persist() {
        let stored = seenFailures.map { ($0.key.uuidString, $0.value) }
        defaults.set(Dictionary(uniqueKeysWithValues: stored), forKey: Key.seen)
    }
}

extension AppCoordinator {
    var agentMark: AgentActivityDot.State? {
        let anchorID = browser.activeAnchorID
        return AgentActivityDot.state(
            isWorking: browser.activeTab?.isAgentWorking == true,
            needsAttention: attention.needsAttention(
                failureCount: anchorID.map { conversationLog.failureCount(forTab: $0) } ?? 0,
                inAnchor: anchorID,
                isShowing: sidePanel.isShowing(.activity)
            )
        )
    }

    func retainAgentMemory() {
        let live = Set(browser.context.extensions.windowAdapters.flatMap { adapter in
            (adapter.browser?.tabs.map(\.id) ?? []) + (adapter.browser?.closedTabs.map(\.tabID) ?? [])
        }).union(browser.tabs.map(\.id)).union(browser.closedTabs.map(\.tabID))
        conversationLog.retainSessionTabs(including: live)
    }
}

enum AgentActivityDot {
    enum State {
        case working
        case attention
    }

    static func state(isWorking: Bool, needsAttention: Bool) -> State? {
        if needsAttention {
            return .attention
        }
        return isWorking ? .working : nil
    }
}

struct AgentInspector: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var activeTabID: UUID? {
        browser.activeTab?.id
    }

    private var activeAnchorID: UUID? {
        browser.activeAnchorID
    }

    private var traces: [ConversationLog.TaskTrace] {
        guard let activeAnchorID else { return [] }
        return coordinator.conversationLog.traces(forTab: activeAnchorID)
    }

    private var failureCount: Int {
        guard let activeAnchorID else { return 0 }
        return coordinator.conversationLog.failureCount(forTab: activeAnchorID)
    }

    @State private var seed: ConversationLog.TaskTrace?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pendingQuestion: AgentQuestionModel.Ask? {
        coordinator.pendingAgentQuestion(inChrome: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if coordinator.voiceConversation.isPresented {
                    AssistantVoiceConversationView(coordinator: coordinator, needsAnswer: pendingQuestion != nil)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .center)))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if let activeTabID {
                            AgentActivityPanel(
                                traces: traces,
                                tabID: activeTabID,
                                browser: browser,
                                isCompacting: coordinator.agentTurns.compactingAnchorID == activeAnchorID
                                    && coordinator.agentTurns.compactingAnchorID != nil
                                    || coordinator.agentReply.isCompacting && coordinator.agentReply.anchorID == activeAnchorID,
                                compactionMessage: coordinator.agentTurns.compactionMessageAnchorID == activeAnchorID
                                    ? coordinator.agentTurns.compactionMessage : nil,
                                onRetry: { trace in
                                    let resumes = trace.canContinue && trace.id == traces.last?.id
                                    if resumes {
                                        coordinator.continueAgent()
                                        return
                                    }
                                    Task {
                                        await coordinator.handleTypedUtterance(
                                            trace.prompt,
                                            attachments: trace.attachments,
                                            showsInChrome: false
                                        )
                                    }
                                },
                                onEdit: { prompt in seed = prompt },
                                speakingAnswerID: coordinator.answerSpeech.speakingAnswerID,
                                readsWithOpenAI: coordinator.voiceRoute.readsWithOpenAI,
                                onSpeak: { trace in coordinator.readAloud(trace.response, id: trace.id) }
                            )
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: pendingQuestion == nil ? .infinity : nil)

            if pendingQuestion != nil {
                AskQuestionBlock(
                    questions: coordinator.agentQuestions,
                    placement: .startPage,
                    takesFocus: false
                )
                .background(Theme.Wash.hairline, in: RoundedRectangle(
                    cornerRadius: Theme.Radius.card,
                    style: .continuous
                ))
                .padding(.horizontal, 12)
                .transition(.opacity)
                .modifier(ChatColumn())
            }

            if !coordinator.voiceConversation.isPresented || pendingQuestion != nil {
                AssistantComposer(coordinator: coordinator, seed: $seed)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .modifier(ChatColumn())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))

                InspectorFooter()
                    .padding(.horizontal, 12)
                    .modifier(ChatColumn())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.45), value: coordinator.voiceConversation.isPresented)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .onChange(of: isShowing, initial: true) { _, _ in
            review()
        }
        .onChange(of: activeAnchorID) { _, _ in
            review()
        }
        .onChange(of: failureCount) { _, _ in
            review()
        }
    }

    private var isShowing: Bool {
        coordinator.sidePanel.isShowing(.activity)
    }

    private func review() {
        coordinator.attention.review(failureCount, inAnchor: activeAnchorID, isShowing: isShowing)
    }
}

private struct ChatColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: AssistantChatMetrics.column, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

private struct InspectorFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AIDisclosure.replyCaption)
                .font(Theme.Font.micro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 2)
        }
    }
}
