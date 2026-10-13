// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct TabProcessStateTests {
    @Test func protectionReasonsUseSafetyFirstPriority() {
        let state = TabProcessState()

        #expect(state.protectionReason(
            isPrivate: false,
            isExtensionPage: false,
            hasDeviceAccess: false,
            hasMediaPlayback: false
        ) == nil)

        state.setAgentWorking(true)
        #expect(reason(from: state, media: true) == .agentWorking)

        state.notePageActivity(.init(kind: .screenShare, token: "share", isActive: true))
        #expect(reason(from: state, device: false, media: true) == .deviceAccess)

        state.notePageActivity(.init(kind: .editedForm, token: "form", isActive: true))
        #expect(reason(from: state, device: true, media: true) == .editedForm)
        #expect(reason(from: state, extensionPage: true, device: true, media: true) == .extensionPage)
        #expect(reason(from: state, privateTab: true, extensionPage: true, device: true, media: true) == .privateBrowsing)
    }

    @Test func externalDeviceAndMediaSignalsProtectTheTab() {
        let state = TabProcessState()

        #expect(reason(from: state, device: true) == .deviceAccess)
        #expect(reason(from: state, media: true) == .mediaPlayback)
    }

    @Test func anEditedFormStaysActiveUntilEveryFrameClears() {
        let state = TabProcessState()

        state.notePageActivity(.init(kind: .editedForm, token: "main", isActive: true))
        state.notePageActivity(.init(kind: .editedForm, token: "frame", isActive: true))
        state.notePageActivity(.init(kind: .editedForm, token: "main", isActive: false))
        #expect(state.hasEditedForm)

        state.notePageActivity(.init(kind: .editedForm, token: "frame", isActive: false))
        #expect(!state.hasEditedForm)
    }

    @Test func aScreenShareStaysActiveUntilEveryFrameClears() {
        let state = TabProcessState()

        state.notePageActivity(.init(kind: .screenShare, token: "main", isActive: true))
        state.notePageActivity(.init(kind: .screenShare, token: "frame", isActive: true))
        state.notePageActivity(.init(kind: .screenShare, token: "main", isActive: false))
        #expect(state.isSharingScreen)

        state.notePageActivity(.init(kind: .screenShare, token: "frame", isActive: false))
        #expect(!state.isSharingScreen)
    }

    @Test func activityTrackingHasABoundedFrameSet() {
        let state = TabProcessState()

        for index in 0..<65 {
            state.notePageActivity(.init(
                kind: .editedForm,
                token: "frame-\(index)",
                isActive: true
            ))
        }
        for index in 0..<64 {
            state.notePageActivity(.init(
                kind: .editedForm,
                token: "frame-\(index)",
                isActive: false
            ))
        }
        #expect(!state.hasEditedForm)

        state.notePageActivity(.init(kind: .editedForm, token: "frame-64", isActive: true))
        #expect(state.hasEditedForm)
        state.notePageActivity(.init(kind: .editedForm, token: "frame-64", isActive: false))
        #expect(!state.hasEditedForm)
    }

    @Test func clearingPageActivityClearsEveryActivityKind() {
        let state = TabProcessState()
        state.notePageActivity(.init(kind: .editedForm, token: "form", isActive: true))
        state.notePageActivity(.init(kind: .screenShare, token: "share", isActive: true))

        state.clearPageActivity()

        #expect(!state.hasEditedForm)
        #expect(!state.isSharingScreen)
    }

    @Test func reclaimStateDescribesUnloadAndReloadTransitions() {
        let state = TabProcessState()

        state.beginReload()
        #expect(state.reclaimState == .none)
        state.markUnloaded()
        #expect(state.reclaimState == .unloaded)
        state.beginReload()
        #expect(state.reclaimState == .reloading)
        state.finishReload()
        #expect(state.reclaimState == .none)
    }

    @Test func repeatedUnexpectedTerminationsAreThrottled() {
        let state = TabProcessState()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(state.shouldReloadAfterUnexpectedTermination(at: start))
        #expect(!state.shouldReloadAfterUnexpectedTermination(at: start.addingTimeInterval(4)))
        #expect(state.shouldReloadAfterUnexpectedTermination(at: start.addingTimeInterval(9)))
    }

    private func reason(
        from state: TabProcessState,
        privateTab: Bool = false,
        extensionPage: Bool = false,
        device: Bool = false,
        media: Bool = false
    ) -> TabProtectionReason? {
        state.protectionReason(
            isPrivate: privateTab,
            isExtensionPage: extensionPage,
            hasDeviceAccess: device,
            hasMediaPlayback: media
        )
    }
}
