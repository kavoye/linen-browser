// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PeekPanel {
    private(set) var tab: BrowserTab?
    @ObservationIgnored private var departures: [UUID: (tab: BrowserTab, task: Task<Void, Never>)] = [:]

    private(set) var ownerID: UUID?

    private(set) var origin: CGPoint = .zero

    private(set) var isQuiet = false
    private(set) var isCollapsed = false

    var isOpen: Bool {
        tab != nil
    }

    func show(_ tab: BrowserTab, from owner: UUID?, at origin: CGPoint) {
        self.tab = tab
        ownerID = owner
        self.origin = origin
        isQuiet = false
        isCollapsed = false
    }

    func aim(at origin: CGPoint) {
        self.origin = origin
        isCollapsed = false
    }

    func setCollapsed(_ collapsed: Bool) {
        guard tab != nil else { return }
        isCollapsed = collapsed
        isQuiet = false
    }

    func belongs(to tabID: UUID) -> Bool {
        ownerID == tabID
    }

    func take(quietly: Bool = false) -> BrowserTab? {
        let held = tab
        isQuiet = quietly
        tab = nil
        ownerID = nil
        isCollapsed = false
        return held
    }

    @discardableResult
    func dismiss(using browser: BrowserModel, clock: any Clock<Duration> = ContinuousClock()) -> Bool {
        guard let held = take() else { return false }
        let task = Task { [weak self, browser] in
            do {
                try await clock.sleep(for: .milliseconds(260))
            } catch {
                return
            }
            guard self?.departures.removeValue(forKey: held.id) != nil else { return }
            browser.dismissPeekTab(held)
        }
        departures[held.id] = (held, task)
        return true
    }

    func dismissImmediately(using browser: BrowserModel) {
        let held = take(quietly: true)
        let pending = Array(departures.values)
        departures.removeAll()
        for departure in pending {
            departure.task.cancel()
            browser.dismissPeekTab(departure.tab)
        }
        if let held {
            browser.dismissPeekTab(held)
        }
    }
}
