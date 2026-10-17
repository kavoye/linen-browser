// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import SwiftUI

@Observable
final class ChromeNotice {
    private(set) var text: String?
    private(set) var symbol: String?
    private(set) var isWarning = false
    private(set) var serial = 0

    @ObservationIgnored private var queued: [(text: String, symbol: String?, isWarning: Bool)] = []
    @ObservationIgnored private var shownAt = ContinuousClock.now
    @ObservationIgnored private var waiting = false
    private static let dwell = Duration.seconds(0.9)
    private static let backlog = 2

    func show(_ message: String, symbol: String? = nil, isWarning: Bool = false) {
        queued.removeAll { $0.text == message }
        queued.append((message, symbol, isWarning))
        if queued.count > Self.backlog {
            queued.removeFirst(queued.count - Self.backlog)
        }
        guard !waiting else { return }
        let wait = text == nil ? .zero : Self.dwell - shownAt.duration(to: .now)
        guard wait > .zero else { return presentNext() }
        waitThenPresent(wait)
    }

    private func waitThenPresent(_ wait: Duration) {
        waiting = true
        Task {
            try? await Task.sleep(for: wait)
            waiting = false
            presentNext()
        }
    }

    private func presentNext() {
        guard !queued.isEmpty else { return }
        let next = queued.removeFirst()
        text = next.text
        symbol = next.symbol
        isWarning = next.isWarning
        serial += 1
        shownAt = .now
        let shown = serial
        if !queued.isEmpty {
            waitThenPresent(Self.dwell)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard serial == shown else { return }
            text = nil
            self.symbol = nil
            self.isWarning = false
        }
    }
}

extension View {
    func noticeWash(_ notice: ChromeNotice, isShowing: Bool, in shape: some Shape) -> some View {
        modifier(NoticeWash(notice: notice, isShowing: isShowing, shape: shape))
    }

    func noticePop(_ notice: ChromeNotice) -> some View {
        modifier(NoticePop(notice: notice))
    }
}

private struct NoticeWash<S: Shape>: ViewModifier {
    let notice: ChromeNotice
    let isShowing: Bool
    let shape: S

    @State private var wash: Double = 0
    @State private var flashing = 0
    @Environment(\.chromeIsLight) private var onLight

    private var color: Color {
        notice.isWarning ? Theme.warning.opacity(0.22) : (onLight ? Color.black : .white).opacity(0.14)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(color)
                    .opacity(isShowing ? wash : 0)
                    .allowsHitTesting(false)
            }
            .onChange(of: notice.serial) { _, _ in flash() }
    }

    private func flash() {
        flashing += 1
        let shown = flashing
        withAnimation(.easeOut(duration: 0.12)) {
            wash = 1
        } completion: {
            guard flashing == shown else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.25)) { wash = 0 }
        }
    }
}

private struct NoticePop: ViewModifier {
    let notice: ChromeNotice

    @State private var pop: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pop)
            .onChange(of: notice.serial) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.14)) {
                    pop = 1.08
                } completion: {
                    withAnimation(.spring(duration: 0.3)) { pop = 1 }
                }
            }
    }
}
