// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct PullState: Equatable {
    var offset: CGFloat = 0
    var progress: CGFloat = 0
    var armed = false
    var tracking = false

    static let idle = PullState()
}

nonisolated struct PullStartProbe: Equatable, Codable {
    struct Ancestor: Equatable, Codable {
        var overflowY: String
        var scrollHeight: Double
        var clientHeight: Double

        var consumesVerticalScroll: Bool {
            (overflowY == "auto" || overflowY == "scroll" || overflowY == "overlay")
                && scrollHeight - clientHeight > 1
        }
    }

    var scrollY: Double
    var ancestors: [Ancestor]

    static func decode(_ answer: String) -> PullStartProbe? {
        try? JSONDecoder().decode(PullStartProbe.self, from: Data(answer.utf8))
    }
}

@MainActor
final class PullToRefreshMonitor {
    var onChange: ((PullState, Animation?) -> Void)?
    var webViewProvider: (() -> WKWebView?)?

    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var startedAtTop: Bool?
    private var disqualified = false
    private var wasArmed = false
    private var topCheck: Task<Void, Never>?
    private var reloadCheck: Task<Void, Never>?

    private static let deadZone: CGFloat = 70
    private static let maxStretch: CGFloat = 150
    private static let give: CGFloat = 0.52
    static let restOffset: CGFloat = 80
    private static let jitter: CGFloat = 2
    nonisolated static let topSlack: Double = 1

    nonisolated static func canBeginPull(_ probe: PullStartProbe) -> Bool {
        probe.scrollY <= topSlack
            && !probe.ancestors.contains(where: \.consumesVerticalScroll)
    }

    static func startProbeScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
          const ancestors = [];
          let node = document.elementFromPoint(\(x), \(y));
          while (node && node !== document.documentElement && node !== document.body) {
            if (node.nodeType !== 1) break;
            const style = getComputedStyle(node);
            ancestors.push({
              overflowY: style.overflowY,
              scrollHeight: node.scrollHeight,
              clientHeight: node.clientHeight
            });
            node = node.parentElement;
          }
          return JSON.stringify({ scrollY: window.scrollY, ancestors });
        })()
        """
    }

    private static let settle = Animation.spring(response: 0.34, dampingFraction: 0.86)

    private static func stretch(for distance: CGFloat) -> CGFloat {
        let pulled = max(0, distance - deadZone)
        return maxStretch * (1 - 1 / (pulled * give / maxStretch + 1))
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        reset(animated: false)
    }

    private func handle(_ event: NSEvent) {
        guard let webView = webViewProvider?(),
              let window = webView.window,
              event.window === window,
              webView.bounds.contains(webView.convert(event.locationInWindow, from: nil)),
              event.momentumPhase == []
        else { return }

        switch event.phase {
        case .began:
            begin(on: webView, at: event.locationInWindow)

        case .changed:
            guard !disqualified else { return }
            let delta = event.scrollingDeltaY
            if delta < -Self.jitter {
                disqualify()
                return
            }
            accumulated = max(0, accumulated + delta)
            publish()

        case .ended:
            finish(on: webView)

        case .cancelled:
            reset()

        default:
            break
        }
    }

    private func begin(on webView: WKWebView, at locationInWindow: NSPoint) {
        topCheck?.cancel()
        reloadCheck?.cancel()
        accumulated = 0
        wasArmed = false
        disqualified = false
        startedAtTop = nil
        onChange?(.idle, nil)

        let local = webView.convert(locationInWindow, from: nil)
        let zoom = webView.pageZoom == 0 ? 1 : webView.pageZoom
        let x = local.x / zoom
        let y = (webView.isFlipped ? local.y : webView.bounds.height - local.y) / zoom

        topCheck = Task { [weak self, weak webView] in
            guard let webView else { return }
            let answer = (try? await webView.evaluateJavaScript(
                Self.startProbeScript(x: x, y: y)
            )) as? String
            guard let self, !Task.isCancelled else { return }
            let probe = answer.flatMap(PullStartProbe.decode)
                ?? PullStartProbe(scrollY: Self.topSlack + 1, ancestors: [])
            if Self.canBeginPull(probe) {
                startedAtTop = true
                publish(Theme.Motion.quick)
            } else {
                disqualify()
            }
        }
    }

    private func publish(_ animation: Animation? = nil) {
        guard startedAtTop == true, !disqualified else { return }
        let offset = Self.stretch(for: accumulated)
        let armed = offset >= Self.restOffset
        if armed, !wasArmed {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        wasArmed = armed
        onChange?(
            PullState(
                offset: offset,
                progress: min(1, offset / Self.restOffset),
                armed: armed,
                tracking: true
            ),
            animation
        )
    }

    private func disqualify() {
        disqualified = true
        accumulated = 0
        wasArmed = false
        onChange?(.idle, Self.settle)
    }

    private func finish(on webView: WKWebView) {
        let earned = startedAtTop == true
            && !disqualified
            && Self.stretch(for: accumulated) >= Self.restOffset
        accumulated = 0
        startedAtTop = nil
        disqualified = false
        wasArmed = false
        topCheck?.cancel()

        onChange?(.idle, Self.settle)
        guard earned else { return }

        reloadCheck = Task { [weak webView] in
            guard let webView else { return }
            let y = (try? await webView.evaluateJavaScript("window.scrollY")) as? Double ?? 1
            guard !Task.isCancelled, y <= Self.topSlack else { return }
            webView.reload()
        }
    }

    private func reset(animated: Bool = true) {
        topCheck?.cancel()
        reloadCheck?.cancel()
        accumulated = 0
        startedAtTop = nil
        disqualified = false
        wasArmed = false
        onChange?(.idle, animated ? Self.settle : nil)
    }
}

struct PullIndicator: View {
    static let size: CGFloat = 32

    let state: PullState

    private var emergence: Double {
        min(1, max(0, (Double(state.progress) - 0.18) * 2.2))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(state.armed
                    ? AnyShapeStyle(Theme.accent)
                    : AnyShapeStyle(Theme.windowBackground.opacity(0.95)))
            Circle()
                .trim(from: 0, to: min(state.progress, 1))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(state.armed ? 0 : 1)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.armed ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .rotationEffect(.degrees(Double(min(state.progress, 1)) * 180))
        }
        .frame(width: Self.size, height: Self.size)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .opacity(state.tracking ? emergence : 0)
        .animation(nil, value: state.tracking)
        .animation(Theme.Motion.settle, value: state.armed)
    }
}
