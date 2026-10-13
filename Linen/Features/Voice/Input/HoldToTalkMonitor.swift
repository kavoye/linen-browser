// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

@MainActor
protocol ActivationSource: AnyObject {
    var onPress: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    func start()
    func stop()
    func reload()
    func setSuspended(_ suspended: Bool)
}

@MainActor
final class HoldToTalkMonitor: ActivationSource {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var localMonitor: Any?
    private var isHolding = false
    private var isSuspended = false

    private let talkSource: () -> ActivationShortcut
    private var talk: ActivationShortcut

    init(talk: @escaping () -> ActivationShortcut = { ActivationSettings.talk }) {
        talkSource = talk
        self.talk = talk()
    }

    private static let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]

    func start() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            let isConsumed = MainActor.assumeIsolated {
                self?.handle(event) == .consumed
            }
            return isConsumed ? nil : event
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        isHolding = false
    }

    func reload() {
        endAnyHold()
        talk = talkSource()
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            endAnyHold()
        }
    }

    private func endAnyHold() {
        guard isHolding else { return }
        isHolding = false
        onRelease?()
    }

    enum Disposition: Equatable {
        case ignored
        case consumed
    }

    func handle(_ event: NSEvent) -> Disposition {
        guard !isSuspended else { return .ignored }

        switch event.type {
        case .flagsChanged:
            if talk.isModifierOnly, event.keyCode == talk.keyCode {
                talkChanged(isDown: talk.isDown(in: event.modifierFlags))
            } else if !talk.modifiers.isSubset(of: event.modifierFlags) {
                endAnyHold()
            }
            return .ignored

        case .keyDown:
            guard !talk.isModifierOnly, talk.matches(event) else { return .ignored }
            if !event.isARepeat {
                talkChanged(isDown: true)
            }
            return .consumed

        case .keyUp:
            guard !talk.isModifierOnly, event.keyCode == talk.keyCode, isHolding else {
                return .ignored
            }
            talkChanged(isDown: false)
            return .consumed

        default:
            return .ignored
        }
    }

    private func talkChanged(isDown: Bool) {
        guard isDown != isHolding else { return }
        isHolding = isDown
        if isDown {
            onPress?()
        } else {
            onRelease?()
        }
    }
}
