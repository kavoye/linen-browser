// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class TabPresentationCover {
    static let ceiling: Duration = .milliseconds(400)
    private static let presentationUpdateSelector = Selector(("_doAfterNextPresentationUpdate:"))

    private(set) var hasPresentedContent = false

    @ObservationIgnored var clock: any Clock<Duration> = ContinuousClock()
    @ObservationIgnored private var hold: Task<Void, Never>?
    @ObservationIgnored private var isArming = false
    @ObservationIgnored private var view: () -> WKWebView?
    @ObservationIgnored private var onUncover: () -> Void

    init(view: @escaping () -> WKWebView?, onUncover: @escaping () -> Void) {
        self.view = view
        self.onUncover = onUncover
    }

    func reset() {
        hasPresentedContent = false
    }

    func cover() {
        hasPresentedContent = false
        hold?.cancel()
        hold = nil
        awaitPresentation()
    }

    func didPresent() {
        guard !hasPresentedContent, let view = view() else { return }
        guard BrowserTab.wouldFlash(
            painting: view.underPageBackgroundColor,
            inDark: view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ) else {
            uncover()
            return
        }
        if hold == nil {
            hold = Task { [weak self, clock] in
                try? await clock.sleep(for: Self.ceiling)
                guard !Task.isCancelled else { return }
                self?.uncover()
            }
        }
        awaitPresentation()
    }

    private func awaitPresentation() {
        guard let view = view(), view.window != nil else { return }
        guard view.responds(to: Self.presentationUpdateSelector) else {
            uncover()
            return
        }
        let done: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isArming {
                    self.uncover()
                } else {
                    self.didPresent()
                }
            }
        }
        isArming = true
        _ = view.perform(Self.presentationUpdateSelector, with: done)
        isArming = false
    }

    private func uncover() {
        guard !hasPresentedContent else { return }
        hold?.cancel()
        hold = nil
        hasPresentedContent = true
        onUncover()
    }
}
