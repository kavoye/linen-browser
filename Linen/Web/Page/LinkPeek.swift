// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class LinkPeek {
    enum Phase: Equatable {
        case loading
        case ready(LinkPeekSummary)
        case stillLoading
        case mediaOnly
        case noText
        case failed
    }

    static func emptyPhase(for page: LinkPeekPage) -> Phase {
        guard page.didFinishLoading else { return .stillLoading }
        return page.mediaCount > 0 ? .mediaOnly : .noText
    }

    struct Shown: Equatable {
        let url: URL
        let tabID: UUID
        var anchor: CGPoint
        var snapshot: NSImage?
        var phase: Phase

        var host: String {
            url.displayHost ?? ""
        }
    }

    nonisolated struct Candidate: Equatable {
        let url: URL
        let tabID: UUID
        let anchor: CGPoint
    }

    private(set) var shown: Shown?

    static let trigger: NSEvent.ModifierFlags = .shift
    private static let holdDelay: Duration = .milliseconds(180)
    private static let rememberedSummaries = 24
    private static let rememberedSnapshots = 6

    private struct Remembered {
        let summary: LinkPeekSummary
        var snapshot: NSImage?
    }

    @ObservationIgnored private let loader = LinkPeekLoader()
    @ObservationIgnored private var candidate: Candidate?
    @ObservationIgnored private var pending: URL?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var remembered: [URL: Remembered] = [:]
    @ObservationIgnored private var order: [URL] = []
    @ObservationIgnored private var isSuppressed = false

    var isEnabled: Bool {
        BrowserSettings.shared.peeksAtLinks && LinkSummarizer.isAvailable
    }

    // MARK: - Lifecycle

    func begin() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.triggerChanged(isDown: event.modifierFlags.contains(Self.trigger))
            }
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forget()
            }
        }
    }

    func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        forget()
        loader.release()
    }

    // MARK: - Pointing

    func hovered(_ url: URL?, flags: NSEvent.ModifierFlags, tabID: UUID, anchor: CGPoint) {
        guard BrowserSettings.shared.peeksAtLinks, !isSuppressed else { return }
        guard let url, LinkPeekLoader.canPeek(url) else {
            forget()
            return
        }
        candidate = Candidate(url: url, tabID: tabID, anchor: anchor)
        guard flags.contains(Self.trigger) else {
            dismiss()
            return
        }
        start()
    }

    func forget() {
        candidate = nil
        dismiss()
    }

    func dismiss() {
        guard shown != nil || pending != nil || work != nil else { return }
        work?.cancel()
        work = nil
        pending = nil
        loader.stop()
        if shown != nil {
            shown = nil
        }
    }

    func suppress() {
        isSuppressed = true
        forget()
    }

    func resume() {
        isSuppressed = false
    }

    private func triggerChanged(isDown: Bool) {
        guard isDown else {
            dismiss()
            return
        }
        start()
    }

    private func start() {
        guard !isSuppressed, let candidate else { return }
        guard shown?.url != candidate.url, pending != candidate.url else { return }
        // `isEnabled` asks for a language model, which is far too heavy to ask
        // on the pointer's path.
        guard isEnabled else { return }

        work?.cancel()
        pending = candidate.url
        let target = candidate
        work = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            await self?.peek(at: target)
        }
    }

    private func peek(at target: Candidate) async {
        if let kept = remembered[target.url] {
            present(target, phase: .ready(kept.summary), snapshot: kept.snapshot)
            return
        }
        present(target, phase: .loading)

        do {
            let page = try await loader.load(target.url)
            try Task.checkCancellation()
            guard shown?.url == target.url else { return }
            shown?.snapshot = page.snapshot

            guard page.hasReadableContent else {
                settle(target.url, to: Self.emptyPhase(for: page))
                return
            }
            guard let summary = await LinkSummarizer.summarize(page, url: target.url) else {
                settle(target.url, to: .failed)
                return
            }
            remember(summary, snapshot: page.snapshot, for: target.url)
            settle(target.url, to: .ready(summary))
        } catch is CancellationError {
            return
        } catch {
            settle(target.url, to: .failed)
        }
    }

    private func present(_ target: Candidate, phase: Phase, snapshot: NSImage? = nil) {
        withAnimation(Theme.Motion.quick) {
            shown = Shown(
                url: target.url,
                tabID: target.tabID,
                anchor: target.anchor,
                snapshot: snapshot,
                phase: phase
            )
        }
    }

    private func settle(_ url: URL, to phase: Phase) {
        guard !Task.isCancelled, shown?.url == url else { return }
        withAnimation(Theme.Motion.settle) {
            shown?.phase = phase
        }
    }

    private func remember(_ summary: LinkPeekSummary, snapshot: NSImage?, for url: URL) {
        if remembered[url] == nil {
            order.append(url)
        }
        remembered[url] = Remembered(summary: summary, snapshot: snapshot)
        while order.count > Self.rememberedSummaries {
            remembered.removeValue(forKey: order.removeFirst())
        }
        // A snapshot is a few megabytes; only the recent ones are worth keeping.
        for old in order.dropLast(Self.rememberedSnapshots) {
            remembered[old]?.snapshot = nil
        }
    }
}
