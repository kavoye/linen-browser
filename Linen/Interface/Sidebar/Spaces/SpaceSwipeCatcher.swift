// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct SpaceSwipeCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> SpaceSwipeView {
        let view = SpaceSwipeView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: SpaceSwipeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    static func dismantleNSView(_ view: SpaceSwipeView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class SpaceSwipeView: NSView {
    var onChange: (CGFloat) -> Void = { _ in }
    var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }

    private enum Lock {
        case elsewhere
        case undecided
        case horizontal
        case vertical
    }

    private static let decisionDistance: CGFloat = 4

    private var monitor: Any?
    private var lock = Lock.elsewhere
    private var pending = CGSize.zero
    private var held: [NSEvent] = []
    private var replaying = 0
    private var travel: CGFloat = 0
    private var recent: [(time: TimeInterval, delta: CGFloat)] = []

    private var velocity: CGFloat {
        guard let last = recent.last else { return 0 }
        let window = recent.filter { last.time - $0.time <= 0.08 }
        guard let first = window.first, last.time > first.time else { return 0 }
        return window.dropFirst().reduce(0) { $0 + $1.delta } / CGFloat(last.time - first.time)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if replaying > 0 {
            replaying -= 1
            return event
        }
        guard event.window === window, event.hasPreciseScrollingDeltas else { return event }
        if !event.momentumPhase.isEmpty {
            return filtered(event)
        }
        switch event.phase {
        case .mayBegin, .began:
            if event.phase == .mayBegin || held.isEmpty {
                let point = convert(event.locationInWindow, from: nil)
                lock = bounds.contains(point) && !isExcluded(event.locationInWindow) ? .undecided : .elsewhere
                pending = .zero
                travel = 0
                recent = []
                held = []
            }
            guard lock == .undecided else { return event }
            held.append(event)
            return nil
        case .changed:
            guard lock == .undecided else {
                if lock == .horizontal {
                    travel += event.scrollingDeltaX
                    recent.append((event.timestamp, event.scrollingDeltaX))
                    if recent.count > 8 {
                        recent.removeFirst()
                    }
                    onChange(travel)
                }
                return filtered(event)
            }
            pending.width += event.scrollingDeltaX
            pending.height += event.scrollingDeltaY
            guard hypot(pending.width, pending.height) >= Self.decisionDistance else { return nil }
            if abs(pending.width) > abs(pending.height) {
                lock = .horizontal
                held = []
                travel = pending.width
                onChange(travel)
                return nil
            }
            lock = .vertical
            return releaseBegin(before: event)
        case .ended, .cancelled:
            switch lock {
            case .horizontal:
                onEnd(travel, velocity)
                return nil
            case .undecided:
                lock = .elsewhere
                return releaseBegin(before: event)
            case .vertical, .elsewhere:
                return filtered(event)
            }
        default:
            return filtered(event)
        }
    }

    private func isExcluded(_ location: NSPoint) -> Bool {
        SpaceSwipeExclusionView.live.allObjects.contains { view in
            view.window === window && view.convert(view.bounds, to: nil).contains(location)
        }
    }

    private func releaseBegin(before event: NSEvent) -> NSEvent? {
        guard let first = held.first else { return filtered(event) }
        let rest = held.dropFirst()
        held = []
        replaying = rest.count + 1
        NSApp.postEvent(Self.verticalOnly(event), atStart: true)
        for later in rest.reversed() {
            NSApp.postEvent(later, atStart: true)
        }
        return first
    }

    private func filtered(_ event: NSEvent) -> NSEvent? {
        switch lock {
        case .horizontal:
            nil
        case .vertical:
            Self.verticalOnly(event)
        case .elsewhere, .undecided:
            event
        }
    }

    private static func verticalOnly(_ event: NSEvent) -> NSEvent {
        guard event.scrollingDeltaX != 0, let copy = event.cgEvent?.copy() else { return event }
        copy.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        copy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
        copy.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        return NSEvent(cgEvent: copy) ?? event
    }
}

struct SpaceSwipeExclusion: NSViewRepresentable {
    func makeNSView(context: Context) -> SpaceSwipeExclusionView {
        SpaceSwipeExclusionView()
    }

    func updateNSView(_ nsView: SpaceSwipeExclusionView, context: Context) {}
}

final class SpaceSwipeExclusionView: NSView {
    static let live = NSHashTable<SpaceSwipeExclusionView>.weakObjects()

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            Self.live.remove(self)
        } else {
            Self.live.add(self)
        }
    }
}
