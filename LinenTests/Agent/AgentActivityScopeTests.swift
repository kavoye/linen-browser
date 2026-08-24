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

    private func newAttention() -> AgentAttention {
        AgentAttention(defaults: scratch())
    }

    private func scratch() -> UserDefaults {
        UserDefaults(suiteName: "AgentAttentionTests-\(UUID().uuidString)")!
    }

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

        let attention = newAttention()
        #expect(attention.needsAttention(
            failureCount: log.failureCount(forTab: tabA), inSpace: tabA, isShowing: false
        ))
        #expect(!attention.needsAttention(
            failureCount: log.failureCount(forTab: tabB), inSpace: tabB, isShowing: false
        ))
    }

    @Test func anUnseenFailureTurnsTheDotOrangeUntilTheColumnOpens() {
        let attention = newAttention()
        let space = UUID()

        #expect(!attention.needsAttention(failureCount: 0, inSpace: space, isShowing: false))
        #expect(attention.needsAttention(failureCount: 1, inSpace: space, isShowing: false))
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: true) == .attention)

        attention.review(1, inSpace: space, isShowing: true)
        #expect(!attention.needsAttention(failureCount: 1, inSpace: space, isShowing: false))

        #expect(AgentActivityDot.state(isWorking: true, needsAttention: false) == .working)
    }

    /// Reviewing one space says nothing about the next one.
    @Test func reviewingOneSpaceLeavesAnotherUnseen() {
        let attention = newAttention()
        let seen = UUID()
        let unseen = UUID()

        attention.review(1, inSpace: seen, isShowing: true)

        #expect(!attention.needsAttention(failureCount: 1, inSpace: seen, isShowing: false))
        #expect(attention.needsAttention(failureCount: 1, inSpace: unseen, isShowing: false))
    }

    @Test func attentionOutranksTheWorkingPulse() {
        #expect(AgentActivityDot.state(isWorking: true, needsAttention: true) == .attention)
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: false) == nil)
    }

    @Test func aFailureWhileTheColumnIsOpenLeavesNoStaleOrange() {
        let attention = newAttention()
        let space = UUID()

        attention.review(1, inSpace: space, isShowing: true)

        #expect(!attention.needsAttention(failureCount: 1, inSpace: space, isShowing: false))
        #expect(attention.needsAttention(failureCount: 2, inSpace: space, isShowing: false))
    }

    @Test func reviewingWhileTheColumnIsHiddenChangesNothing() {
        let attention = newAttention()
        let space = UUID()

        attention.review(3, inSpace: space, isShowing: false)

        #expect(attention.needsAttention(failureCount: 3, inSpace: space, isShowing: false))
    }

    @Test func theDotNeverLightsWhileYouAreLookingAtTheColumn() {
        let attention = newAttention()

        #expect(!attention.needsAttention(failureCount: 9, inSpace: UUID(), isShowing: true))
    }

    // MARK: - What was seen stays seen

    @Test func aFailureSeenInOneLaunchIsStillSeenInTheNext() {
        let defaults = scratch()
        let space = UUID()
        AgentAttention(defaults: defaults).review(1, inSpace: space, isShowing: true)

        let relaunched = AgentAttention(defaults: defaults)

        #expect(!relaunched.needsAttention(failureCount: 1, inSpace: space, isShowing: false))
        #expect(
            relaunched.needsAttention(failureCount: 2, inSpace: space, isShowing: false),
            "a later failure is news again"
        )
    }

    @Test func aSpaceThatIsGoneTakesWhatWasSeenWithIt() {
        let defaults = scratch()
        let attention = AgentAttention(defaults: defaults)
        attention.review(1, inSpace: UUID(), isShowing: true)

        attention.retainSpaces([UUID()])

        #expect(attention.seenFailures.isEmpty)
        #expect(AgentAttention(defaults: defaults).seenFailures.isEmpty)
    }

    @Test func aSpaceThatIsStillOpenKeepsWhatWasSeen() {
        let space = UUID()
        let attention = newAttention()
        attention.review(1, inSpace: space, isShowing: true)

        attention.retainSpaces([space, UUID()])

        #expect(attention.seenFailures[space] == 1)
    }

    // MARK: - The footer disclaimer

    @Test func theFooterDisclaimerFitsOneLineAtMinimumWidth() {
        let caption = String(localized: AIDisclosure.replyCaption)
        let width = (caption as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
            .width
        let budget = SidePanelMetrics.minWidth - 24 - 2

        #expect(width <= budget)
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
    func discardAllSessions() {}
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
