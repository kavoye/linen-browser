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
            guard let spaceID = UUID(uuidString: entry.key) else { return }
            found[spaceID] = entry.value
        }
    }

    func review(_ count: Int, inSpace spaceID: UUID?, isShowing: Bool) {
        guard isShowing, let spaceID else { return }
        let seen = max(seenFailures[spaceID] ?? 0, count)
        guard seenFailures[spaceID] != seen else { return }
        seenFailures[spaceID] = seen
        persist()
    }

    func needsAttention(failureCount: Int, inSpace spaceID: UUID?, isShowing: Bool) -> Bool {
        guard !isShowing, let spaceID else { return false }
        return failureCount > (seenFailures[spaceID] ?? 0)
    }

    func retainSpaces(_ spaceIDs: Set<UUID>) {
        let kept = seenFailures.filter { spaceIDs.contains($0.key) }
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
        let spaceID = browser.activeSpaceID
        return AgentActivityDot.state(
            isWorking: browser.activeTab?.isAgentWorking == true,
            needsAttention: attention.needsAttention(
                failureCount: spaceID.map { conversationLog.failureCount(forTab: $0) } ?? 0,
                inSpace: spaceID,
                isShowing: sidePanel.isShowing(.activity)
            )
        )
    }

    func retainAgentMemory() {
        let live = Set(browser.tabs.map(\.id))
        conversationLog.retainTabs(live)
        attention.retainSpaces(live)
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

    private var activeSpaceID: UUID? {
        browser.activeSpaceID
    }

    private var traces: [ConversationLog.TaskTrace] {
        guard let activeSpaceID else { return [] }
        return coordinator.conversationLog.traces(forTab: activeSpaceID)
    }

    private var failureCount: Int {
        guard let activeSpaceID else { return 0 }
        return coordinator.conversationLog.failureCount(forTab: activeSpaceID)
    }

    @State private var seed: ConversationLog.TaskTrace?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pendingQuestion: AgentQuestionModel.Ask? {
        coordinator.agentQuestions.ask(inSpace: activeSpaceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if coordinator.isVoiceConversationPresented {
                    AssistantVoiceConversationView(coordinator: coordinator, needsAnswer: pendingQuestion != nil)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .center)))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ResearchGlimpse(preview: coordinator.researchPreview, activeSpaceID: activeSpaceID)
                            .padding(.horizontal, 12)

                        if let activeTabID {
                            AgentActivityPanel(
                                traces: traces,
                                tabID: activeTabID,
                                browser: browser,
                                isCompacting: coordinator.agentTurns.compactingSpaceID == activeSpaceID
                                    && coordinator.agentTurns.compactingSpaceID != nil
                                    || coordinator.agentReply.isCompacting && coordinator.agentReply.spaceID == activeSpaceID,
                                compactionMessage: coordinator.agentTurns.compactionMessageSpaceID == activeSpaceID
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
                                onSpeak: { answer in coordinator.readAloud(answer) }
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

            if !coordinator.isVoiceConversationPresented || pendingQuestion != nil {
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
        .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.45), value: coordinator.isVoiceConversationPresented)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .onChange(of: isShowing, initial: true) { _, _ in
            review()
        }
        .onChange(of: activeSpaceID) { _, _ in
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
        coordinator.attention.review(failureCount, inSpace: activeSpaceID, isShowing: isShowing)
    }
}

private struct ChatColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: AssistantChatMetrics.column, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

private struct ResearchGlimpse: View {
    let preview: ResearchPreview
    let activeSpaceID: UUID?

    private static var maxSnapshotWidth: CGFloat {
        SidePanelMetrics.minWidth - 24
    }

    var body: some View {
        if let snapshot = preview.snapshot, preview.spaceID == activeSpaceID, preview.isLive {
            VStack(alignment: .leading, spacing: 5) {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: Self.maxSnapshotWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.Wash.selection, lineWidth: 1)
                    )

                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                    Text(caption)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            .animation(Theme.Motion.settle, value: preview.isLive)
        }
    }

    private var caption: LocalizedStringResource {
        let place = preview.host ?? String(localized: "the research page")
        return "Browsing \(place)…"
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
