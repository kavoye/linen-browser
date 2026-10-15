// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct AgentActivityScopeTests {
    // MARK: - The toolbar preview (the reply strip)

    @Test func aReplyOnlySurfacesInTheAnchorItBelongsTo() {
        let reply = AgentReplyModel()
        let controlled = UUID()
        let other = UUID()

        reply.bind(toAnchor: controlled)
        reply.beginStream()
        reply.setActivity("Searching the web")

        #expect(reply.message(inAnchor: controlled) == "Searching the web")
        #expect(reply.message(inAnchor: other) == nil)
        #expect(reply.message(inAnchor: nil) == nil)

        reply.setActivity(nil)
        reply.update(text: "Found it.")
        #expect(reply.message(inAnchor: controlled) == "Found it.")
        #expect(reply.message(inAnchor: other) == nil)
    }

    @Test func anUnboundReplySurfacesNowhere() {
        let reply = AgentReplyModel()
        reply.beginStream()
        reply.update(text: "Orphan reply")

        #expect(reply.message(inAnchor: UUID()) == nil)
    }

    @Test func aTurnBindsItsReplyToTheSessionAnchor() async throws {
        let browser = FakeScopeBrowser()
        let log = FakeScopeLog()
        let model = AgentTurnModel(browser: browser, log: log, speech: FakeScopeSpeech())
        model.use(FakeScopeRunner())

        #expect(model.run(utterance: "look this up"))
        #expect(model.reply.anchorID == browser.tabID)

        #expect(await waitUntil { !model.isRunning })
        #expect(!model.isRunning)
        #expect(model.reply.anchorID == browser.tabID)
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
        UserDefaults(suiteName: TestDefaults.name("AgentAttentionTests"))!
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

    /// A failure from another tab once made the activity indicator open an empty panel.
    @Test func aFailureOnOneTabLeavesTheOtherTabsDotAlone() {
        let log = ConversationLog(database: .temporary())
        let tabA = UUID()
        let tabB = UUID()

        log.failTask(log.beginTask("doomed", tabID: tabA), reason: "Network died.")

        #expect(log.failureCount(forTab: tabA) == 1)
        #expect(log.failureCount(forTab: tabB) == 0)

        let attention = newAttention()
        #expect(attention.needsAttention(
            failureCount: log.failureCount(forTab: tabA), inAnchor: tabA, isShowing: false
        ))
        #expect(!attention.needsAttention(
            failureCount: log.failureCount(forTab: tabB), inAnchor: tabB, isShowing: false
        ))
    }

    @Test func anUnseenFailureTurnsTheDotOrangeUntilTheColumnOpens() {
        let attention = newAttention()
        let anchor = UUID()

        #expect(!attention.needsAttention(failureCount: 0, inAnchor: anchor, isShowing: false))
        #expect(attention.needsAttention(failureCount: 1, inAnchor: anchor, isShowing: false))
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: true) == .attention)

        attention.review(1, inAnchor: anchor, isShowing: true)
        #expect(!attention.needsAttention(failureCount: 1, inAnchor: anchor, isShowing: false))

        #expect(AgentActivityDot.state(isWorking: true, needsAttention: false) == .working)
    }

    @Test func reviewingOneAnchorLeavesAnotherUnseen() {
        let attention = newAttention()
        let seen = UUID()
        let unseen = UUID()

        attention.review(1, inAnchor: seen, isShowing: true)

        #expect(!attention.needsAttention(failureCount: 1, inAnchor: seen, isShowing: false))
        #expect(attention.needsAttention(failureCount: 1, inAnchor: unseen, isShowing: false))
    }

    @Test func attentionOutranksTheWorkingPulse() {
        #expect(AgentActivityDot.state(isWorking: true, needsAttention: true) == .attention)
        #expect(AgentActivityDot.state(isWorking: false, needsAttention: false) == nil)
    }

    @Test func aFailureWhileTheColumnIsOpenLeavesNoStaleOrange() {
        let attention = newAttention()
        let anchor = UUID()

        attention.review(1, inAnchor: anchor, isShowing: true)

        #expect(!attention.needsAttention(failureCount: 1, inAnchor: anchor, isShowing: false))
        #expect(attention.needsAttention(failureCount: 2, inAnchor: anchor, isShowing: false))
    }

    @Test func reviewingWhileTheColumnIsHiddenChangesNothing() {
        let attention = newAttention()
        let anchor = UUID()

        attention.review(3, inAnchor: anchor, isShowing: false)

        #expect(attention.needsAttention(failureCount: 3, inAnchor: anchor, isShowing: false))
    }

    @Test func theDotNeverLightsWhileYouAreLookingAtTheColumn() {
        let attention = newAttention()

        #expect(!attention.needsAttention(failureCount: 9, inAnchor: UUID(), isShowing: true))
    }

    // MARK: - What was seen stays seen

    @Test func aFailureSeenInOneLaunchIsStillSeenInTheNext() {
        let defaults = scratch()
        let anchor = UUID()
        AgentAttention(defaults: defaults).review(1, inAnchor: anchor, isShowing: true)

        let relaunched = AgentAttention(defaults: defaults)

        #expect(!relaunched.needsAttention(failureCount: 1, inAnchor: anchor, isShowing: false))
        #expect(
            relaunched.needsAttention(failureCount: 2, inAnchor: anchor, isShowing: false),
            "a later failure is news again"
        )
    }

    @Test func anAnchorThatIsGoneTakesWhatWasSeenWithIt() {
        let defaults = scratch()
        let attention = AgentAttention(defaults: defaults)
        attention.review(1, inAnchor: UUID(), isShowing: true)

        attention.retainAnchors([UUID()])

        #expect(attention.seenFailures.isEmpty)
        #expect(AgentAttention(defaults: defaults).seenFailures.isEmpty)
    }

    @Test func anAnchorThatIsStillOpenKeepsWhatWasSeen() {
        let anchor = UUID()
        let attention = newAttention()
        attention.review(1, inAnchor: anchor, isShowing: true)

        attention.retainAnchors([anchor, UUID()])

        #expect(attention.seenFailures[anchor] == 1)
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
    func agentAnchorID(forTab tabID: UUID) -> UUID {
        tabID
    }
    func agentContextSummary(mentionedTabIDs: [UUID]) -> String? {
        nil
    }
    func setAgentWorking(_ isWorking: Bool, inAnchor anchorID: UUID) {}
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
