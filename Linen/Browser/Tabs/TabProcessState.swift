// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class TabProcessState {
    private(set) var hasEditedForm = false
    private(set) var isSharingScreen = false
    private(set) var isAgentWorking = false
    private(set) var reclaimState: TabReclaimState = .none

    @ObservationIgnored private var editedFormFrames: Set<String> = []
    @ObservationIgnored private var screenShareFrames: Set<String> = []
    @ObservationIgnored private var lastUnexpectedTermination: Date?

    private static let maximumActiveFrames = 64
    private static let terminationRetryInterval: TimeInterval = 5

    func protectionReason(
        isPrivate: Bool,
        isExtensionPage: Bool,
        hasDeviceAccess: Bool,
        hasMediaPlayback: Bool
    ) -> TabProtectionReason? {
        if isPrivate {
            return .privateBrowsing
        }
        if isExtensionPage {
            return .extensionPage
        }
        if hasEditedForm {
            return .editedForm
        }
        if isSharingScreen || hasDeviceAccess {
            return .deviceAccess
        }
        if isAgentWorking {
            return .agentWorking
        }
        if hasMediaPlayback {
            return .mediaPlayback
        }
        return nil
    }

    func setAgentWorking(_ isWorking: Bool) {
        isAgentWorking = isWorking
    }

    func notePageActivity(_ signal: PageActivitySignal) {
        switch signal.kind {
        case .editedForm:
            updateActivitySet(&editedFormFrames, with: signal)
            hasEditedForm = !editedFormFrames.isEmpty
        case .screenShare:
            updateActivitySet(&screenShareFrames, with: signal)
            isSharingScreen = !screenShareFrames.isEmpty
        }
    }

    func clearPageActivity() {
        editedFormFrames.removeAll(keepingCapacity: true)
        screenShareFrames.removeAll(keepingCapacity: true)
        hasEditedForm = false
        isSharingScreen = false
    }

    func markUnloaded() {
        reclaimState = .unloaded
    }

    func beginReload() {
        reclaimState = reclaimState == .unloaded ? .reloading : .none
    }

    func finishReload() {
        reclaimState = .none
    }

    func shouldReloadAfterUnexpectedTermination(at date: Date = Date()) -> Bool {
        defer { lastUnexpectedTermination = date }
        guard let lastUnexpectedTermination else { return true }
        return date.timeIntervalSince(lastUnexpectedTermination) >= Self.terminationRetryInterval
    }

    private func updateActivitySet(
        _ set: inout Set<String>,
        with signal: PageActivitySignal
    ) {
        if signal.isActive {
            guard set.count < Self.maximumActiveFrames || set.contains(signal.token) else { return }
            set.insert(signal.token)
        } else {
            set.remove(signal.token)
        }
    }
}
