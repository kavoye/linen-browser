// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import WebKit

extension WKWebView {
    func evaluateJavaScript<Value: Sendable>(
        _ script: String, in world: WKContentWorld = .page, within ceiling: Duration, as type: Value.Type
    ) async -> Value? {
        await PageReply.awaiting(within: ceiling) { gate in
            evaluateJavaScript(script, in: nil, in: world) { result in
                gate.finish((try? result.get()) as? Value)
            }
        }
    }

    func callAsyncJavaScript<Value: Sendable>(
        _ body: String, arguments: [String: Any] = [:], in world: WKContentWorld,
        within ceiling: Duration, as type: Value.Type
    ) async -> Value? {
        await PageReply.awaiting(within: ceiling) { gate in
            callAsyncJavaScript(body, arguments: arguments, in: nil, in: world) { result in
                gate.finish((try? result.get()) as? Value)
            }
        }
    }
}

/// Resumes its caller once, with the first of the page's answer, the caller's cancellation or the
/// ceiling.
@MainActor
final class PageReply<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?
    private var ceiling: Task<Void, Never>?
    private var isFinished = false

    private init() {}

    func finish(_ value: Value?) {
        guard !isFinished else { return }
        isFinished = true
        ceiling?.cancel()
        continuation?.resume(returning: value)
        continuation = nil
    }

    static func awaiting(within ceiling: Duration, _ start: (PageReply<Value>) -> Void) async -> Value? {
        let gate = PageReply<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.continuation = continuation
                guard !Task.isCancelled else {
                    gate.finish(nil)
                    return
                }
                gate.ceiling = Task {
                    try? await Task.sleep(for: ceiling)
                    gate.finish(nil)
                }
                start(gate)
            }
        } onCancel: {
            Task { @MainActor in gate.finish(nil) }
        }
    }
}
