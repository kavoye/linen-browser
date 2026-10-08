// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
@preconcurrency import Translation

extension AppCoordinator {
    func translatePage(_ tab: BrowserTab, to target: Locale.Language? = nil) {
        guard tab.isShowingRealPage else { return }
        if let target {
            tab.context.settings.translationTarget = target
        }
        let downloads = translationDownloads
        let chosen = target ?? tab.translation.targets.first ?? tab.context.settings.translationTarget
        Task {
            await tab.translate(to: chosen) { model, source, target in
                await downloads.prepare(model, from: source, to: target)
            }
        }
    }

    func openPreferredLanguages() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func showOriginal(_ tab: BrowserTab) {
        tab.translation.showOriginal(in: tab.isMaterialised ? tab.translationSurface : nil)
    }

    func toggleTranslation(_ tab: BrowserTab) {
        if tab.translation.isActive {
            showOriginal(tab)
        } else {
            translatePage(tab)
        }
    }
}

@MainActor
@Observable
final class TranslationDownloads {
    private(set) var configuration: TranslationSession.Configuration?

    @ObservationIgnored private var pending: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Bool, Never>] = []

    func prepare(_ model: TranslationModel, from source: Locale.Language, to target: Locale.Language) async -> Bool {
        let key = "\(model)|\(TranslationLanguage.key(source))|\(TranslationLanguage.key(target))"
        if pending != key {
            finish(false)
            pending = key
            generation += 1
            configuration = model.configuration(from: source, to: target)
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func run(preparing: () async -> Bool) async {
        guard pending != nil else { return }
        let expected = generation
        let prepared = await preparing()
        guard generation == expected else { return }
        finish(prepared && !Task.isCancelled)
    }

    func abandon() {
        guard pending != nil else { return }
        generation += 1
        finish(false)
    }

    private func finish(_ prepared: Bool) {
        let resumed = waiters
        waiters = []
        pending = nil
        configuration = nil
        for waiter in resumed {
            waiter.resume(returning: prepared)
        }
    }
}

struct TranslationDownloadHost: ViewModifier {
    let downloads: TranslationDownloads

    func body(content: Content) -> some View {
        content.translationTask(downloads.configuration) { session in
            await downloads.run {
                (try? await session.prepareTranslation()) != nil
            }
        }
        .onDisappear { downloads.abandon() }
    }
}
