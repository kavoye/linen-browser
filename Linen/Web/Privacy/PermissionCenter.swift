// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class TabPermissionCenter {
    enum AskAnswer {
        case deny
        case once
        case always
        case dismissed
    }

    struct Ask: Identifiable {
        let id = UUID()
        let permission: WebPermission
        let origin: String
        fileprivate var waiting: [CheckedContinuation<Outcome, Never>] = []

        var waitingCount: Int {
            waiting.count
        }
    }

    private let store: SitePermissions

    private(set) var origin: String = ""

    var displayHost: String {
        SitePermissions.displayName(for: origin)
    }

    private(set) var isSecure = false

    var persistsAnswers = true

    private(set) var pendingAsks: [Ask] = []
    private(set) var sessionGrants: Set<WebPermission> = []
    private(set) var sessionDenies: Set<WebPermission> = []
    private(set) var touched: Set<WebPermission> = []
    private(set) var live: Set<WebPermission> = []

    var isPopoverPresented = false

    var onRevoke: ((WebPermission) -> Void)?

    init(store: SitePermissions = .shared) {
        self.store = store
    }

    // MARK: - The gate

    enum Outcome {
        case granted
        case denied
        case undecided
    }

    func decide(_ permission: WebPermission) async -> Bool {
        await outcome(permission) == .granted
    }

    func outcome(_ permission: WebPermission) async -> Outcome {
        touched.insert(permission)
        guard !origin.isEmpty else { return .undecided }
        guard isSecure else {
            sessionDenies.insert(permission)
            return .denied
        }
        switch store.policy(for: origin, permission) {
        case .allow:
            return .granted
        case .deny:
            return .denied
        case .ask:
            break
        }
        if sessionGrants.contains(permission) {
            return .granted
        }
        if sessionDenies.contains(permission) {
            return .denied
        }
        return await withCheckedContinuation { continuation in
            if let index = pendingAsks.firstIndex(where: { $0.permission == permission }) {
                pendingAsks[index].waiting.append(continuation)
            } else {
                pendingAsks.append(Ask(permission: permission, origin: origin, waiting: [continuation]))
            }
            isPopoverPresented = true
        }
    }

    func isGranted(_ permission: WebPermission) -> Bool {
        guard isSecure else { return false }
        return store.policy(for: origin, permission) == .allow || sessionGrants.contains(permission)
    }

    func answer(_ answer: AskAnswer) {
        guard !pendingAsks.isEmpty else { return }
        let ask = pendingAsks.removeFirst()
        record(answer, for: ask)
        resolve(ask, with: outcome(for: answer))
        if pendingAsks.isEmpty {
            isPopoverPresented = false
        }
    }

    private func record(_ answer: AskAnswer, for ask: Ask) {
        switch answer {
        case .deny:
            if persistsAnswers {
                store.set(.deny, for: ask.origin, ask.permission)
            } else {
                sessionDenies.insert(ask.permission)
            }
        case .once:
            sessionGrants.insert(ask.permission)
        case .always:
            if persistsAnswers {
                store.set(.allow, for: ask.origin, ask.permission)
            } else {
                sessionGrants.insert(ask.permission)
            }
        case .dismissed:
            break
        }
    }

    private func outcome(for answer: AskAnswer) -> Outcome {
        switch answer {
        case .once, .always:
            .granted
        case .deny:
            .denied
        case .dismissed:
            .undecided
        }
    }

    private func resolve(_ ask: Ask, with outcome: Outcome) {
        for continuation in ask.waiting {
            continuation.resume(returning: outcome)
        }
    }

    var currentAsk: Ask? {
        pendingAsks.first
    }

    // MARK: - Site changes

    func pageChanged(url: URL?) {
        let secure = SitePermissions.isPotentiallyTrustworthy(url)
        let newOrigin = SitePermissions.origin(for: url)
        guard newOrigin != origin || secure != isSecure else { return }
        origin = newOrigin
        isSecure = secure
        let orphaned = pendingAsks
        pendingAsks = []
        for ask in orphaned {
            resolve(ask, with: .undecided)
        }
        sessionGrants = []
        sessionDenies = []
        touched = []
        live = []
        isPopoverPresented = false
    }

    func siteDataCleared() {
        sessionGrants = []
        sessionDenies = []
        for permission in live {
            onRevoke?(permission)
        }
        live = []
        touched = []
    }

    // MARK: - Live state

    func setLive(_ permission: WebPermission, _ isLive: Bool) {
        if isLive {
            live.insert(permission)
            touched.insert(permission)
        } else {
            live.remove(permission)
        }
    }

    // MARK: - Changing an answer

    func set(_ policy: PermissionPolicy, for permission: WebPermission) {
        guard isSecure || policy != .allow else { return }
        if persistsAnswers {
            store.set(policy, for: origin, permission)
        } else {
            sessionGrants.remove(permission)
            sessionDenies.remove(permission)
            switch policy {
            case .allow:
                sessionGrants.insert(permission)
            case .deny:
                sessionDenies.insert(permission)
            case .ask:
                break
            }
        }
        if policy != .allow {
            sessionGrants.remove(permission)
            if live.contains(permission) {
                live.remove(permission)
                onRevoke?(permission)
            }
        }
    }

    // MARK: - What the badge and popover show

    enum BadgeFace: Equatable {
        case hidden
        case asking(WebPermission)
        case live(WebPermission)
        case denied(WebPermission)
        case granted(WebPermission)
    }

    var badge: BadgeFace {
        for permission in [WebPermission.camera, .microphone, .location] where live.contains(permission) {
            return .live(permission)
        }
        if let ask = pendingAsks.first {
            return .asking(ask.permission)
        }
        let rows = self.rows
        if let denied = rows.first(where: { $0.state == .denied }) {
            return .denied(denied.permission)
        }
        if let granted = rows.first(where: { $0.state != .denied }) {
            return .granted(granted.permission)
        }
        return .hidden
    }

    enum RowState: Equatable {
        case live(always: Bool)
        case always
        case session
        case denied
        case asks
    }

    struct Row: Identifiable, Equatable {
        let permission: WebPermission
        let state: RowState
        var id: WebPermission {
            permission
        }
    }

    var rows: [Row] {
        let recorded = store.recordedPermissions(for: origin)
        return WebPermission.allCases.compactMap { permission in
            let policy = recorded[permission]
            guard touched.contains(permission)
                || sessionGrants.contains(permission)
                || sessionDenies.contains(permission)
                || live.contains(permission)
                || policy != nil
            else { return nil }
            let state: RowState
            if live.contains(permission) {
                state = .live(always: policy == .allow)
            } else if policy == .allow {
                state = .always
            } else if policy == .deny || sessionDenies.contains(permission) {
                state = .denied
            } else if sessionGrants.contains(permission) {
                state = .session
            } else {
                state = .asks
            }
            return Row(permission: permission, state: state)
        }
    }

    func menuPolicy(for permission: WebPermission) -> PermissionPolicy {
        isSecure ? store.policy(for: origin, permission) : .deny
    }
}
