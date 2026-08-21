// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

/// What the activity column has already been seen to contain, so the mark on
/// the Activity tab only lights for failures the user has not looked at. It
/// outlives the launch it was seen in, because the failures do too.
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

    /// Spaces that are gone take what was seen in them with them.
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
    /// The one mark the Activity tab carries, wherever it is drawn: on the
    /// panel's own button while the panel is away, and on the tab itself once
    /// the panel is open on something else.
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

    private var usage: ConversationLog.Usage {
        guard let activeSpaceID else { return .zero }
        return coordinator.conversationLog.usage(forTab: activeSpaceID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResearchGlimpse(preview: coordinator.researchPreview, activeSpaceID: activeSpaceID)
                .padding(.horizontal, 12)

            if let activeTabID {
                AgentActivityPanel(
                    traces: traces,
                    tabID: activeTabID,
                    browser: browser,
                    onRetry: { prompt in
                        Task { await coordinator.handleTypedUtterance(prompt) }
                    }
                )
            } else {
                Spacer(minLength: 0)
            }

            InspectorFooter(coordinator: coordinator, usage: usage)
                .padding(.horizontal, 12)
        }
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

private struct ResearchGlimpse: View {
    let preview: ResearchPreview
    let activeSpaceID: UUID?

    var body: some View {
        if let snapshot = preview.snapshot, preview.spaceID == activeSpaceID {
            VStack(alignment: .leading, spacing: 5) {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.Wash.selection, lineWidth: 1)
                    )
                    .opacity(preview.isLive ? 1 : 0.55)

                HStack(spacing: 5) {
                    Circle()
                        .fill(preview.isLive ? Theme.accent : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(caption)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            .transition(.opacity)
            .animation(Theme.Motion.settle, value: preview.isLive)
        }
    }

    private var caption: LocalizedStringResource {
        let place = preview.host ?? String(localized: "the research page")
        let caption: LocalizedStringResource = preview.isLive
            ? "Browsing \(place)…"
            : "Finished on \(place)"
        return caption
    }
}

private struct InspectorFooter: View {
    let coordinator: AppCoordinator
    let usage: ConversationLog.Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModelChip(coordinator: coordinator)

            if usage.requestCount > 0 {
                AgentUsageSummary(usage: usage)
                    .padding(.leading, ModelChipMetrics.textInset)
            }

            Text(AIDisclosure.replyCaption)
                .font(Theme.Font.micro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 2)
        }
    }
}
