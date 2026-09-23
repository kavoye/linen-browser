// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import XCTest

@testable import Linen

// XCTest owns and runs one instance serially. Sendable lets its synchronous
// callbacks enter the app target's main-actor boundary.
nonisolated final class AgentActivityFreezeTests: XCTestCase, @unchecked Sendable {
    /// AppKit text heights once disagreed with lazy-stack estimates, causing repeated layout.
    /// Require the run loop to become idle while streaming and scrolling at minimum width.
    func testStreamingAndScrollingTracesNeverWedgesTheMainRunLoop() {
        MainActor.assumeIsolated {
            let browser = BrowserModel(database: .temporary())
            defer { browser.cancelPendingSave() }
            let tabID = UUID()
            var traces = Self.worstCaseTraces(tabID: tabID, count: 40)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 268, height: 620),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            defer { window.orderOut(nil) }
            let host = NSHostingView(rootView: Self.panel(traces, tabID: tabID, browser: browser))
            host.frame = NSRect(x: 0, y: 0, width: 268, height: 620)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            window.layoutIfNeeded()
            window.displayIfNeeded()

            XCTAssertTrue(
                mainRunLoopReachesIdle(within: 30),
                "initial layout of the activity panel never settled"
            )

            let streamed = Self.worstCaseTraces(tabID: tabID, count: 8)
            for var arriving in streamed {
                let finished = arriving
                arriving.response = ""
                arriving.state = .running
                traces.append(arriving)
                host.rootView = Self.panel(traces, tabID: tabID, browser: browser)
                guard mainRunLoopReachesIdle(within: 15) else {
                    XCTFail("main run loop never settled after a new trace arrived")
                    return
                }
                for fraction in [3, 2, 1] {
                    traces[traces.count - 1].response = String(
                        finished.response.prefix(finished.response.count / fraction)
                    )
                    host.rootView = Self.panel(traces, tabID: tabID, browser: browser)
                    guard mainRunLoopReachesIdle(within: 15) else {
                        XCTFail("main run loop never settled while a response streamed in")
                        return
                    }
                }
                traces[traces.count - 1].state = .completed
            }

            host.rootView = Self.panel(traces, tabID: tabID, browser: browser)
            window.layoutIfNeeded()
            guard mainRunLoopReachesIdle(within: 15) else {
                XCTFail("completed traces never settled")
                return
            }

            guard let scrollView = firstScrollView(in: host) else {
                XCTFail("no NSScrollView behind the panel's ScrollView")
                return
            }
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            guard viewportHeight > 0, documentHeight > viewportHeight else {
                XCTFail("the activity panel must have a visible, scrollable viewport")
                return
            }
            let scrollStep = viewportHeight / 2
            let maximumSteps = Int(ceil(max(0, documentHeight - viewportHeight) / scrollStep)) + 1
            let layoutTolerance = 1 / window.backingScaleFactor
            var step = 0
            while true {
                let currentHeight = scrollView.documentView?.frame.height ?? 0
                let visibleHeight = scrollView.contentView.bounds.height
                let y = min(
                    CGFloat(step) * scrollStep,
                    max(0, currentHeight - visibleHeight)
                )
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                window.displayIfNeeded()
                guard mainRunLoopReachesIdle(within: 15) else {
                    XCTFail("main run loop never settled after scrolling to \(Int(y)) of \(Int(currentHeight))")
                    return
                }
                if y >= currentHeight - visibleHeight {
                    break
                }
                step += 1
                if step > maximumSteps {
                    XCTFail("scroll range never converged: initial=\(documentHeight), current=\(scrollView.documentView?.frame.height ?? 0), viewport=\(viewportHeight), step=\(step), y=\(y)")
                    return
                }
            }

            XCTAssertEqual(
                scrollView.documentView?.frame.height ?? 0,
                documentHeight,
                accuracy: layoutTolerance,
                "scrolling must not change the activity panel's measured content height"
            )
        }
    }

    @MainActor
    private static func panel(
        _ traces: [ConversationLog.TaskTrace],
        tabID: UUID,
        browser: BrowserModel
    ) -> AgentActivityPanel {
        AgentActivityPanel(
            traces: traces,
            tabID: tabID,
            browser: browser,
            onRetry: { _ in },
            onEdit: { _ in },
            onSpeak: { _ in }
        )
    }

    /// Idle means a `.beforeWaiting` pass *after* Core Animation's commit
    /// observer (order 2,000,000): the layout graph flushed and stayed clean.
    @MainActor
    private func mainRunLoopReachesIdle(within timeout: TimeInterval) -> Bool {
        let idle = XCTestExpectation(description: "main run loop reached .beforeWaiting")
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            false,
            2_500_000
        ) { _, _ in
            idle.fulfill()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        defer {
            if let observer, CFRunLoopObserverIsValid(observer) {
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
        }
        return XCTWaiter().wait(for: [idle], timeout: timeout) == .completed
    }

    @MainActor
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func worstCaseTraces(tabID: UUID, count: Int) -> [ConversationLog.TaskTrace] {
        let paragraph = """
        The agent compared prices across several retailers and found \
        meaningful differences between the configurations on offer. Shipping \
        estimates ranged widely, and two of the listings bundled accessories \
        that changed the effective total enough to reorder the ranking.
        """
        return (0..<count).map { index in
            let steps = (0..<6).map { stepIndex in
                ConversationLog.Step(
                    kind: .tool,
                    title: "Search the web for “a deliberately long query \(index)-\(stepIndex) that wraps at the panel's minimum width”",
                    toolName: "searchWeb",
                    detail: Array(repeating: paragraph, count: 4).joined(separator: "\n\n"),
                    links: [],
                    state: .completed
                )
            }
            return ConversationLog.TaskTrace(
                id: UUID(),
                tabID: tabID,
                prompt: "Worst-case prompt \(index): compare a dozen listings and explain the trade-offs in detail",
                startedAt: Date(timeIntervalSinceNow: Double(index - count) * 60),
                steps: steps,
                response: Array(repeating: paragraph, count: 5).joined(separator: "\n\n"),
                state: .completed,
                finishedAt: Date(timeIntervalSinceNow: Double(index - count) * 60 + 30),
                providerID: nil
            )
        }
    }
}
