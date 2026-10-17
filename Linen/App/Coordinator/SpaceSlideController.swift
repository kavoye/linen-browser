// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import QuartzCore
import SwiftUI

@MainActor
final class SpaceSlideController {
    let glide = SpaceGlide()
    private(set) var isLanding = false

    private unowned let coordinator: AppCoordinator
    private var turn = 0
    private var landing = 0
    private var landedAt: ContinuousClock.Instant?
    private var restWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    private var slide: SpaceSlide {
        coordinator.overlays.spaceSlide
    }

    private var browser: BrowserModel {
        coordinator.browser
    }

    private var spaceStore: SpaceStore {
        coordinator.spaceStore
    }

    var isAtRest: Bool {
        !isLanding && !slide.isSliding
    }

    @discardableResult
    private func nextTurn() -> Int {
        turn += 1
        return turn
    }

    // MARK: - Rest

    func untilAtRest() async {
        guard !isAtRest else { return }
        let id = UUID()
        await withCheckedContinuation { continuation in
            restWaiters[id] = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let waiter = self?.restWaiters.removeValue(forKey: id) else { return }
                Pipeline.log.error("spaces: gave up waiting for the slide to rest")
                waiter.resume()
            }
        }
    }

    private func noteRest() {
        guard isAtRest else { return }
        let waiters = restWaiters.values
        restWaiters = [:]
        waiters.forEach { $0.resume() }
    }

    private func snap(_ change: (SpaceSlide) -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            change(slide)
        }
    }

    private static func roll(velocity: Double = 0) -> Animation {
        .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: velocity)
    }

    // MARK: - Peers

    func mountPeers() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !slide.isSliding else { return }
            var ids: [UUID] = []
            if coordinator.showsSpaces, let current = browser.currentSpaceID {
                ids = [
                    spaceStore.neighbor(of: current, forward: false)?.id,
                    current,
                    spaceStore.neighbor(of: current, forward: true)?.id,
                ].compactMap { $0 }
            }
            for id in ids {
                coordinator.preparePeerModel(for: id)
            }
            glide.prewarm(ids)
        }
    }

    func pageColorWillChange(on tab: BrowserTab) {
        guard let landedAt, ContinuousClock.now - landedAt < .milliseconds(1500),
              !slide.isSliding, tab === browser.activeTab else { return }
        coordinator.crossfadeNextFrame()
    }

    // MARK: - Switching

    func switchSpace(to space: Space) {
        guard space.id != browser.currentSpaceID, !isLanding else { return }
        guard coordinator.overlays.spaceEditor == nil, !coordinator.settings.isMinimal else {
            jump(to: space)
            return
        }
        let order = spaceStore.spaces.map(\.id)
        let from = browser.currentSpaceID.flatMap { order.firstIndex(of: $0) } ?? 0
        let to = order.firstIndex(of: space.id) ?? 0
        glide(to: space, forward: to > from, velocity: 0)
    }

    func canSwipe(forward: Bool) -> Bool {
        browser.currentSpaceID.flatMap { spaceStore.neighbor(of: $0, forward: forward) } != nil
    }

    private func switchToNeighbor(forward: Bool) {
        guard let current = browser.currentSpaceID,
              let next = spaceStore.neighbor(of: current, forward: forward) else { return }
        coordinator.switchSpace(to: next)
    }

    func follow(_ tab: BrowserTab, in model: BrowserModel) {
        guard let id = tab.spaceID else { return }
        guard model === browser else {
            model.switchSpace(to: id, showing: tab)
            return
        }
        guard let space = spaceStore.space(id: id) else { return }
        guard !isLanding else {
            Task { [weak self] in
                await self?.untilAtRest()
                guard let self, model.activeTab === tab, tab.spaceID != model.currentSpaceID else { return }
                follow(tab, in: model)
            }
            return
        }
        jump(to: space)
    }

    func land(in id: UUID) {
        browser.switchSpace(to: id)
    }

    func jump(to space: Space) {
        guard space.id != browser.currentSpaceID else { return }
        settle()
        enter(space)
    }

    private func enter(_ space: Space) {
        guard let profile = coordinator.foreignProfile(of: space) else {
            browser.switchSpace(to: space.id)
            mountPeers()
            return
        }
        isLanding = true
        Task { [weak self] in
            await self?.coordinator.switchProfile(to: profile, landingIn: space.id)
            self?.isLanding = false
            self?.noteRest()
        }
    }

    // MARK: - Swiping

    func drag(to travel: CGFloat) {
        guard !isLanding else { return }
        nextTurn()
        let forward = travel < 0
        let neighbor = browser.currentSpaceID.flatMap { spaceStore.neighbor(of: $0, forward: forward) }
        let peer = neighbor.map { SpacePeer(id: $0.id, forward: forward) }
        let offset = peer == nil
            ? max(-60, min(60, travel * 0.15))
            : max(-slide.width, min(slide.width, travel))
        let pull = peer == nil && forward ? min(1, abs(travel) / max(slide.width * 0.45, 1)) : 0
        let loomTravel = peer == nil ? 0 : (min(1, abs(offset) / max(slide.width, 1)) * 48).rounded() / 48
        let loom = slide.peer != peer ? neighbor.flatMap { coordinator.loomColor(forSpace: $0.id) } : slide.peerLoom
        if let peer, slide.peer != peer {
            coordinator.preparePeerModel(for: peer.id)
        }
        let staged = browser.currentSpaceID.map {
            glide.track(from: $0, to: peer?.id, forward: forward, offset: offset, width: slide.width, scroll: slide.scroll)
        } ?? false
        snap {
            if !$0.isSliding {
                $0.isSliding = true
            }
            if $0.isStaged != staged {
                $0.isStaged = staged
            }
            if $0.peer != peer {
                $0.peer = peer
                $0.peerLoom = loom
            }
            if $0.loomTravel != loomTravel {
                $0.loomTravel = loomTravel
            }
            $0.offset = offset
            if $0.pull != pull {
                $0.pull = pull
            }
        }
    }

    func endSwipe(travel: CGFloat, velocity: CGFloat = 0) {
        guard !isLanding else { return }
        let forward = travel < 0
        if slide.peer == nil, slide.pull >= 1 {
            cancel()
            openEditor(.new)
            return
        }
        let flicked = abs(velocity) > 300 && (velocity < 0) == forward && abs(travel) > 20
        guard abs(travel) > slide.width * 0.25 || flicked, canSwipe(forward: forward) else {
            cancel()
            return
        }
        guard slide.peer?.forward == forward, let target = slide.peer.flatMap({ spaceStore.space(id: $0.id) }) else {
            cancel()
            switchToNeighbor(forward: forward)
            return
        }
        let remaining = max(slide.width - abs(slide.offset), 1)
        let speed = (velocity < 0) == forward ? abs(velocity) : 0
        glide(to: target, forward: forward, velocity: min(speed / remaining, 12))
    }

    private func glide(to space: Space, forward: Bool, velocity: Double) {
        guard let outgoing = browser.currentSpaceID else { return }
        let turn = nextTurn()
        landing += 1
        let landingTurn = landing
        let offset = slide.peer == SpacePeer(id: space.id, forward: forward) ? slide.offset : 0
        var glided = false
        var switched = false
        let land = { [weak self] in
            guard let self, glided, switched, landing == landingTurn else { return }
            isLanding = false
            glide.finish()
            snap { $0.reset() }
            mountPeers()
            noteRest()
        }
        coordinator.preparePeerModel(for: space.id)
        let started = glide.run(
            from: outgoing,
            to: space.id,
            forward: forward,
            offset: offset,
            width: slide.width,
            scroll: slide.scroll,
            velocity: velocity
        ) {
            glided = true
            land()
        }
        guard started else {
            jump(to: space)
            return
        }
        isLanding = true
        snap {
            $0.isStaged = true
            $0.isSliding = true
        }
        let target = SpaceGlideTarget(from: outgoing, to: space.id, loom: coordinator.loomColor(forSpace: space.id))
        slide.glideTurn = turn
        slide.glideVelocity = velocity
        withAnimation(Self.roll(velocity: velocity)) {
            slide.gliding = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) { [weak self] in
            guard let self, !coordinator.isClosed, landing == landingTurn else { return }
            coordinator.nativeWindow?.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            guard let profile = coordinator.foreignProfile(of: space) else {
                snap {
                    $0.held = self.browser.sidebarItems
                    self.browser.switchSpace(to: space.id)
                }
                landedAt = .now
                switched = true
                land()
                return
            }
            Task { [weak self] in
                var landed = false
                await self?.coordinator.switchProfile(to: profile, landingIn: space.id) {
                    landed = true
                    self?.landedAt = .now
                }
                guard landed else {
                    self?.settle()
                    return
                }
                switched = true
                land()
            }
        }
    }

    func cancel() {
        let turn = nextTurn()
        glide.settleBack { [weak self] in
            self?.snap { $0.isStaged = false }
            self?.mountPeers()
        }
        withAnimation(Self.roll(), completionCriteria: .removed) {
            slide.offset = 0
            slide.loomTravel = 0
            slide.pull = 0
        } completion: { [weak self] in
            guard let self, self.turn == turn else { return }
            snap {
                $0.peer = nil
                $0.isSliding = false
            }
            mountPeers()
            noteRest()
        }
    }

    func settle() {
        nextTurn()
        landing += 1
        isLanding = false
        glide.finish()
        snap { $0.reset() }
        mountPeers()
        noteRest()
    }

    // MARK: - Editor

    func openEditor(_ target: SpaceEditorTarget) {
        guard coordinator.overlays.spaceEditor != target, !isLanding else { return }
        nextTurn()
        snap { $0.isSliding = true }
        withAnimation(Theme.Motion.drift) {
            coordinator.overlays.spaceEditor = target
        }
    }

    func closeEditor() {
        guard coordinator.overlays.spaceEditor != nil, !isLanding else { return }
        let turn = nextTurn()
        withAnimation(Theme.Motion.drift) {
            coordinator.overlays.spaceEditor = nil
        } completion: { [weak self] in
            guard let self, self.turn == turn else { return }
            snap { $0.isSliding = false }
            noteRest()
        }
    }

    func enterCreated(_ space: Space) {
        guard coordinator.overlays.spaceEditor != nil else {
            coordinator.switchSpace(to: space)
            return
        }
        let overlays = coordinator.overlays
        let leave = { [weak self] in
            guard let self else { return }
            nextTurn()
            var still = Transaction(animation: nil)
            still.disablesAnimations = true
            withTransaction(still) {
                overlays.spaceAppearance = 0
                overlays.spaceEditorRevealsList = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.034) { [weak self] in
                guard let self else { return }
                withAnimation(.easeOut(duration: 0.38)) {
                    overlays.spaceEditorExit = 1
                    overlays.spaceAppearance = 1
                } completion: { [weak self] in
                    guard let self else { return }
                    withTransaction(still) {
                        overlays.spaceEditor = nil
                        overlays.spaceEditorExit = 0
                        overlays.spaceEditorRevealsList = false
                    }
                    snap { $0.isSliding = false }
                    mountPeers()
                    noteRest()
                }
            }
        }
        guard let profile = coordinator.foreignProfile(of: space) else {
            browser.switchSpace(to: space.id)
            leave()
            return
        }
        isLanding = true
        Task { [weak self] in
            await self?.coordinator.switchProfile(to: profile, landingIn: space.id)
            self?.isLanding = false
            leave()
        }
    }
}
