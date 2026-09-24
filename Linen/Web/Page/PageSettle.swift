// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
enum PageSettle {
    static let loadCeiling: Duration = .seconds(12)
    static let navigationGrace: Duration = .milliseconds(400)
    @TaskLocal static var interactionObserver: (@MainActor @Sendable () -> Void)?

    @discardableResult
    static func untilIdle(
        _ webView: WKWebView,
        timeout: Duration = loadCeiling,
        clock: some Clock<Duration> = ContinuousClock()
    ) async -> Bool {
        await wait(on: webView, timeout: timeout, clock: clock) { !$0.isLoading }
    }

    static func afterInteraction(
        _ webView: WKWebView,
        grace: Duration = navigationGrace,
        quietCeiling: Duration = .milliseconds(1500),
        clock: some Clock<Duration> = ContinuousClock()
    ) async {
        interactionObserver?()
        let navigated = await wait(on: webView, timeout: grace, clock: clock) { $0.isLoading }
        if navigated {
            await untilIdle(webView, clock: clock)
        }
        await untilQuiet(webView, ceiling: quietCeiling, clock: clock)
    }

    static func untilQuiet(
        _ webView: WKWebView,
        ceiling: Duration = .milliseconds(2500),
        interval: Duration = .milliseconds(120),
        clock: some Clock<Duration> = ContinuousClock()
    ) async {
        var monitor = QuiescenceMonitor()
        let deadline = clock.now.advanced(by: ceiling)
        while clock.now < deadline, !Task.isCancelled {
            let remaining = clock.now.duration(to: deadline)
            guard let signature = await signature(of: webView, timeout: remaining) else { return }
            if monitor.record(signature) {
                return
            }
            do {
                try await clock.sleep(for: max(.zero, min(interval, clock.now.duration(to: deadline))))
            } catch { return }
        }
    }

    private static func signature(of webView: WKWebView, timeout: Duration) async -> Int? {
        let script = """
        (() => {
          const elements = document.getElementsByTagName('*').length;
          const text = document.body ? document.body.textContent.length : 0;
          const ready = document.readyState === 'complete' ? 1 : 0;
          return elements * 1000003 + text * 7 + ready;
        })()
        """
        return await withCheckedContinuation { continuation in
            let gate = PageSettleSignatureGate(continuation)
            webView.evaluateJavaScript(script) { value, _ in
                let signature = (value as? NSNumber)?.intValue
                Task.detached(priority: .userInitiated) {
                    await gate.close(with: signature)
                }
            }
            let timeoutTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await gate.close(with: nil)
            }
            Task.detached(priority: .userInitiated) {
                await gate.install(timeoutTask)
            }
        }
    }

    private static func wait(
        on webView: WKWebView,
        timeout: Duration,
        clock: some Clock<Duration>,
        until isSatisfied: @escaping @MainActor (WKWebView) -> Bool
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        if isSatisfied(webView) {
            return true
        }
        let gate = Gate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.arm(continuation)
                gate.observation = webView.observe(\.isLoading, options: [.new]) { view, _ in
                    MainActor.assumeIsolated {
                        if isSatisfied(view) {
                            gate.close(satisfied: true)
                        }
                    }
                }
                gate.timeoutTask = Task {
                    try? await clock.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    gate.close(satisfied: false)
                }
                if isSatisfied(webView) {
                    gate.close(satisfied: true)
                }
            }
        } onCancel: {
            Task { @MainActor in gate.close(satisfied: false) }
        }
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Bool, Never>?
        var observation: NSKeyValueObservation?
        var timeoutTask: Task<Void, Never>?

        func arm(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func close(satisfied: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            observation?.invalidate()
            observation = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(returning: satisfied)
        }
    }
}

private actor PageSettleSignatureGate {
    private var continuation: CheckedContinuation<Int?, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Int?, Never>) {
        self.continuation = continuation
    }

    func install(_ task: Task<Void, Never>) {
        guard continuation != nil else {
            task.cancel()
            return
        }
        timeoutTask = task
    }

    func close(with signature: Int?) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: signature)
    }
}

nonisolated struct QuiescenceMonitor {
    private var previous: Int?
    private var matches = 0
    private let required: Int

    init(requiredMatches: Int = 2) {
        required = requiredMatches
    }

    mutating func record(_ signature: Int) -> Bool {
        if signature == previous {
            matches += 1
        } else {
            previous = signature
            matches = 1
        }
        return matches >= required
    }
}
