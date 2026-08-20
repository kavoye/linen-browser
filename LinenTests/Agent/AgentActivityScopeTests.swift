// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

/// A space - one tab, or every pane of a split - owns its agent activity.
/// These tests pin the three surfaces that could leak it - the toolbar's live
/// preview, the inspector's research thumbnail, and the activity dot - to the
/// space the agent is working.
@MainActor
struct AgentActivityScopeTests {
    // MARK: - The toolbar preview (the reply strip)

    @Test func aReplyOnlySurfacesInTheSpaceItBelongsTo() {
        let reply = AgentReplyModel()
        let controlled = UUID()
        let other = UUID()

        reply.bind(toSpace: controlled)
        reply.beginStream()
        reply.setActivity("Searching the web")

        #expect(reply.message(inSpace: controlled) == "Searching the web")
        #expect(reply.message(inSpace: other) == nil)
        #expect(reply.message(inSpace: nil) == nil)

        reply.setActivity(nil)
        reply.update(text: "Found it.")
        #expect(reply.message(inSpace: controlled) == "Found it.")
        #expect(reply.message(inSpace: other) == nil)
    }

    @Test func anUnboundReplySurfacesNowhere() {
        let reply = AgentReplyModel()
        reply.beginStream()
        reply.update(text: "Orphan reply")

        #expect(reply.message(inSpace: UUID()) == nil)
    }

    @Test func aTurnBindsItsReplyToTheSessionSpace() async throws {
        let browser = FakeScopeBrowser()
        let log = FakeScopeLog()
        let model = AgentTurnModel(browser: browser, log: log, speech: FakeScopeSpeech())
        model.use(FakeScopeRunner())

        #expect(model.run(utterance: "look this up"))
        #expect(model.reply.spaceID == browser.tabID)

        for _ in 0..<10_000 {
            if !model.isRunning {
                break
            }
            await Task.yield()
        }
        #expect(!model.isRunning)
        #expect(model.reply.spaceID == browser.tabID)
    }

    // MARK: - The research thumbnail

    @Test func theResearchPreviewBelongsToTheTaskSpace() {
        let preview = ResearchPreview()
        let controlled = UUID()
        let other = UUID()

        preview.begin(inSpace: controlled)
        #expect(preview.spaceID == controlled)
        #expect(preview.spaceID != other)

        preview.end()
        #expect(preview.spaceID == controlled)

        preview.begin(inSpace: other)
        #expect(preview.spaceID == other)
        #expect(preview.snapshot == nil)
    }

    // MARK: - The log's tab boundary

    @Test func activityOnOneTabIsInvisibleFromAnother() {
        let log = ConversationLog(database: .temporary())
        let tabA = UUID()
        let tabB = UUID()

        _ = log.beginTask("do a thing", tabID: tabA)

        #expect(log.isRunning(onTab: tabA))
        #expect(!log.isRunning(onTab: tabB))
        #expect(log.hasActivity(forTab: tabA))
        #expect(!log.hasActivity(forTab: tabB))
        #expect(log.traces(forTab: tabB).isEmpty)
        #expect(log.latestTrace(forTab: tabB) == nil)
    }

    // MARK: - The activity dot

    @Test func aFailedTurnRaisesTheFailureCount() {
        let log = ConversationLog(database: .temporary())
        let tab = UUID()

        log.completeTask(log.beginTask("fine", tabID: tab), response: "done")
        log.cancelTask(log.beginTask("stopped", tabID: tab))
        #expect(log.failureCount(forTab: tab) == 0)

        log.failTask(log.beginTask("doomed", tabID: tab), reason: "Network died.")
        #expect(log.failureCount(forTab: tab) == 1)
    }

    /// The dot points at a column the click will fill. A failure on another tab
    /// used to travel with it and open an empty column.
    @Test func aFailureOnOneTabLeavesTheOtherTabsDotAlone() {
        let log = ConversationLog(database: .temporary())
        let tabA = UUID()
        let tabB = UUID()

        log.failTask(log.beginTask("doomed", tabID: tabA), reason: "Network died.")

        #expect(log.failureCount(forTab: tabA) == 1)
        #expect(log.failureCount(forTab: tabB) == 0)

        let layout = scratchLayout()
        #expect(layout.needsAttention(failureCount: log.failureCount(forTab: tabA), inSpace: tabA))
        #expect(!layout.needsAttention(failureCount: log.failureCount(forTab: tabB), inSpace: tabB))
    }

    @Test func anUnseenFailureTurnsTheDotOrangeUntilTheColumnOpens() {
        let layout = scratchLayout()
        let space = UUID()

        #expect(!layout.needsAttention(failureCount: 0, inSpace: space))
        #expect(layout.needsAttention(failureCount: 1, inSpace: space))
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: true) == .attention)

        layout.show()
        layout.reviewFailures(1, inSpace: space)
        layout.close()
        #expect(!layout.needsAttention(failureCount: 1, inSpace: space))

        #expect(AgentActivityDot.state(isWorking: true, needsAttention: false) == .working)
    }

    /// Reviewing one space says nothing about the next one.
    @Test func reviewingOneSpaceLeavesAnotherUnseen() {
        let layout = scratchLayout()
        let seen = UUID()
        let unseen = UUID()

        layout.show()
        layout.reviewFailures(1, inSpace: seen)
        layout.close()

        #expect(!layout.needsAttention(failureCount: 1, inSpace: seen))
        #expect(layout.needsAttention(failureCount: 1, inSpace: unseen))
    }

    @Test func attentionOutranksTheWorkingPulse() {
        #expect(AgentActivityDot.state(isWorking: true, needsAttention: true) == .attention)
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: false) == nil)
    }

    @Test func aFailureWhileTheColumnIsOpenLeavesNoStaleOrange() {
        let layout = scratchLayout()
        let space = UUID()

        layout.show()
        layout.reviewFailures(1, inSpace: space)
        layout.close()

        #expect(!layout.needsAttention(failureCount: 1, inSpace: space))
        #expect(layout.needsAttention(failureCount: 2, inSpace: space))
    }

    @Test func reviewingWhileClosedChangesNothing() {
        let layout = scratchLayout()
        let space = UUID()

        layout.reviewFailures(3, inSpace: space)
        #expect(layout.needsAttention(failureCount: 3, inSpace: space))
    }

    // MARK: - The footer disclaimer

    @Test func theFooterDisclaimerFitsOneLineAtMinimumWidth() {
        let caption = String(localized: AIDisclosure.replyCaption)
        let width = (caption as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
            .width
        let budget = InspectorMetrics.minWidth - 24 - 2

        #expect(width <= budget)
    }

    private func scratchLayout() -> InspectorLayout {
        let defaults = UserDefaults(suiteName: "AgentActivityScopeTests-\(UUID().uuidString)")!
        return InspectorLayout(defaults: defaults)
    }
}

@MainActor
private final class FakeScopeBrowser: AgentTurnBrowsing {
    let tabID = UUID()

    func ensureAgentTabID() -> UUID {
        tabID
    }
    func agentSpaceID(forTab tabID: UUID) -> UUID {
        tabID
    }
    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        nil
    }
    func setAgentWorking(_ isWorking: Bool, inSpace spaceID: UUID) {}
}

@MainActor
private final class FakeScopeLog: AgentTurnLogging {
    func beginTask(_ prompt: String, tabID: UUID) -> UUID {
        UUID()
    }
    func completeTask(_ taskID: UUID, response: String) {}
    func cancelTask(_ taskID: UUID) {}
    func removeTab(_ tabID: UUID) {}
    func reassign(from tabID: UUID, to newTabID: UUID) {}
}

@MainActor
private final class FakeScopeRunner: AgentRunner {
    let name = "Scope runner"

    func prepare() {}
    func discardSession(forTab tabID: UUID) {}
    func transferSession(from tabID: UUID, to newTabID: UUID) {}

    func run(
        utterance: String,
        task: AgentTaskContext,
        into reply: AgentReplyModel,
        speech: any SpeechOutput
    ) async {
        reply.beginStream()
        reply.update(text: "done")
        reply.endStream(retainFor: 60)
    }
}

@MainActor
private final class FakeScopeSpeech: SpeechOutput {
    var isMuted = false
    var onSpeakingChange: ((Bool) -> Void)?

    func speak(_ text: String) {}
    func stopSpeaking() {}
}
