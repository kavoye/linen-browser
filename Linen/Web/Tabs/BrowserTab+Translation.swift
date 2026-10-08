// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
@preconcurrency import Translation

extension BrowserTab {
    var canToggleTranslation: Bool {
        translation.isActive || (isMaterialised && !isShowingError && !translation.targets.isEmpty)
    }

    func offerTranslation() {
        guard isShowingRealPage, !isShowingError, !translation.isActive else { return }
        let webView = webView
        let document = translation.document
        let settings = context.settings
        Task {
            var detected: Locale.Language?
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(1.5))
                }
                guard translation.document == document, !isClosed else { return }
                detected = await translation.detectLanguage(in: webView)
                if detected != nil {
                    break
                }
            }
            guard let source = detected, translation.document == document else { return }
            let candidates = TranslationLanguage.targets(for: source, preferring: settings.translationTargetID)
            let targets = await TranslationLanguage.translatable(candidates, from: source)
            guard translation.document == document, !isClosed else { return }
            translation.offer(targets)
            guard let target = targets.first, settings.alwaysTranslates(source) else { return }
            await translate(to: target, downloading: nil)
        }
    }

    func translationPageMoved() {
        guard !isLoading, !translation.isActive else { return }
        translation.pageMoved()
        offerTranslation()
    }

    func translate(
        to target: Locale.Language,
        downloading prepare: ((TranslationModel, Locale.Language, Locale.Language) async -> Bool)?
    ) async {
        let webView = translationSurface
        let request = translation.begin(to: target)
        guard let source = await translation.detectLanguage(in: webView),
              translation.isCurrent(request), !TranslationLanguage.matches(source, target),
              let model = await TranslationModel.choose(from: source, to: target, downloading: prepare),
              translation.isCurrent(request), !isClosed
        else {
            translation.abandon(request, in: isMaterialised ? webView : nil)
            return
        }
        translation.translate(request, in: webView, from: source, using: model)
    }
}
