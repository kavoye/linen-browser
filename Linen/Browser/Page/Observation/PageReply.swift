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

@MainActor
final class PageReply<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?

    private init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value?) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    static func awaiting(within ceiling: Duration, _ start: (PageReply<Value>) -> Void) async -> Value? {
        await withCheckedContinuation { continuation in
            let gate = PageReply(continuation)
            start(gate)
            Task {
                try? await Task.sleep(for: ceiling)
                gate.finish(nil)
            }
        }
    }
}
