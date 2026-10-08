// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import NaturalLanguage
import OSLog
@preconcurrency import Translation
import WebKit

@MainActor
@Observable
final class PageTranslation {
    enum Phase: Equatable {
        case original
        case translating
        case translated
    }

    private(set) var phase: Phase = .original
    private(set) var target: Locale.Language?
    private(set) var detectedLanguage: Locale.Language?
    private(set) var hasDetected = false
    private(set) var targets: [Locale.Language] = []

    @ObservationIgnored private(set) var document = 0
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var detection: Task<Locale.Language?, Never>?

    var isActive: Bool {
        phase != .original
    }

    func documentChanged() {
        document += 1
        request += 1
        job?.cancel()
        job = nil
        detection?.cancel()
        detection = nil
        phase = .original
        target = nil
        detectedLanguage = nil
        hasDetected = false
        targets = []
    }

    func offer(_ targets: [Locale.Language]) {
        self.targets = targets
    }

    func detectLanguage(in webView: WKWebView) async -> Locale.Language? {
        if hasDetected {
            return detectedLanguage
        }
        if let detection {
            return await detection.value
        }
        let expected = document
        let task = Task { () -> Locale.Language? in
            guard let sample = await PageTranslationScript.sample(in: webView) else { return nil }
            return await TranslationLanguage.detectInBackground(sample)
        }
        detection = task
        let language = await task.value
        guard document == expected else { return nil }
        detection = nil
        detectedLanguage = language
        hasDetected = language != nil
        return language
    }

    func pageMoved() {
        guard !isActive else { return }
        document += 1
        detection?.cancel()
        detection = nil
        detectedLanguage = nil
        hasDetected = false
        targets = []
    }

    func begin(to target: Locale.Language) -> Int {
        request += 1
        job?.cancel()
        job = nil
        self.target = target
        phase = .translating
        return request
    }

    func isCurrent(_ request: Int) -> Bool {
        self.request == request
    }

    func abandon(_ request: Int, in webView: WKWebView?) {
        guard isCurrent(request) else { return }
        showOriginal(in: webView)
    }

    func translate(
        _ request: Int,
        in webView: WKWebView,
        from source: Locale.Language,
        using model: TranslationModel
    ) {
        guard isCurrent(request), let target else { return }
        job = Task { [weak self, weak webView] in
            guard let page = webView, let token = await PageTranslationScript.start(in: page) else {
                self?.abandon(request, in: nil)
                return
            }
            let session = model.session(from: source, to: target)
            let skipper = TranslationLanguage.Skipper(source: source, target: target)
            var translatedAny = false
            var failedAny = false
            while let self, let webView, isCurrent(request), !Task.isCancelled {
                guard let blocks = await PageTranslationScript.next(limit: 4, token: token, in: webView) else { return }
                guard isCurrent(request), !Task.isCancelled else { return }
                if blocks.isEmpty {
                    if failedAny, !translatedAny {
                        TranslationModel.log.notice("every block failed; showing the original")
                        abandon(request, in: webView)
                        return
                    }
                    if phase == .translating {
                        phase = .translated
                    }
                    continue
                }
                for segments in blocks {
                    guard await !skipper.isAlreadyTarget(segments) else { continue }
                    let texts = await PageTranslationRuns.translate(segments, with: session)
                    guard isCurrent(request), !Task.isCancelled else { return }
                    guard let texts else {
                        failedAny = true
                        continue
                    }
                    translatedAny = true
                    await PageTranslationScript.apply(texts, in: webView)
                }
            }
        }
    }

    func showOriginal(in webView: WKWebView?) {
        guard isActive else { return }
        request += 1
        job?.cancel()
        job = nil
        phase = .original
        target = nil
        guard let webView else { return }
        Task { await PageTranslationScript.restore(in: webView) }
    }
}

enum TranslationModel: Equatable {
    case fast
    case accurate

    static let log = Logger(subsystem: "com.kavoye.Linen", category: "translation")

    static func choose(
        from source: Locale.Language,
        to target: Locale.Language,
        downloading prepare: ((TranslationModel, Locale.Language, Locale.Language) async -> Bool)?
    ) async -> TranslationModel? {
        let pair = "\(TranslationLanguage.key(source))>\(TranslationLanguage.key(target))"
        let fastStatus = await fast.status(from: source, to: target)
        if fastStatus == .installed {
            log.notice("\(pair, privacy: .public): fast model")
            return .fast
        }
        if await accurate.status(from: source, to: target) == .installed {
            if fastStatus == .supported, let prepare {
                Task { _ = await prepare(.fast, source, target) }
            }
            log.notice("\(pair, privacy: .public): accurate model, fast model not installed")
            return .accurate
        }
        guard fastStatus == .supported, let prepare else {
            log.notice("\(pair, privacy: .public): no model available")
            return nil
        }
        let prepared = await prepare(.fast, source, target)
        let installed = await fast.status(from: source, to: target) == .installed
        log.notice("\(pair, privacy: .public): download prepared=\(prepared) installed=\(installed)")
        return prepared && installed ? .fast : nil
    }

    func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        if #available(macOS 26.4, *) {
            return await LanguageAvailability(preferredStrategy: strategy).status(from: source, to: target)
        }
        return await LanguageAvailability().status(from: source, to: target)
    }

    func session(from source: Locale.Language, to target: Locale.Language) -> TranslationSession {
        if #available(macOS 26.4, *) {
            return TranslationSession(installedSource: source, target: target, preferredStrategy: strategy)
        }
        return TranslationSession(installedSource: source, target: target)
    }

    func configuration(from source: Locale.Language, to target: Locale.Language) -> TranslationSession.Configuration {
        if #available(macOS 26.4, *) {
            return TranslationSession.Configuration(source: source, target: target, preferredStrategy: strategy)
        }
        return TranslationSession.Configuration(source: source, target: target)
    }

    @available(macOS 26.4, *)
    private var strategy: TranslationSession.Strategy {
        self == .fast ? .lowLatency : .highFidelity
    }
}

enum PageTranslationRuns {
    private static let scheme = "linen-node"

    static func translate(_ segments: [PageTranslationSegment], with session: TranslationSession) async -> [Int: String]? {
        let nodes = segments.map(\.node)
        if #available(macOS 26.4, *) {
            guard let response = try? await session.translate(request(for: segments)) else { return nil }
            return distribute(response.attributedTargetText, fallback: response.targetText, over: nodes)
        }
        guard let response = try? await session.translate(segments.map(\.text).joined()) else { return nil }
        return distribute(nil, fallback: response.targetText, over: nodes)
    }

    static func request(for segments: [PageTranslationSegment]) -> AttributedString {
        var request = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            part.link = URL(string: "\(scheme):\(segment.node)")
            request += part
        }
        return request
    }

    static func distribute(_ translated: AttributedString?, fallback: String, over nodes: [Int]) -> [Int: String] {
        guard let first = nodes.first else { return [:] }
        var texts = Dictionary(uniqueKeysWithValues: nodes.map { ($0, "") })
        guard let translated else {
            texts[first] = fallback
            return texts
        }
        var current = first
        for run in translated.runs {
            if let link = run.link, link.scheme == scheme, let node = Int(link.absoluteString.dropFirst(scheme.count + 1)),
               texts[node] != nil {
                current = node
            }
            texts[current, default: ""] += String(translated[run.range].characters)
        }
        return texts
    }
}

nonisolated enum TranslationLanguage {
    static var preferred: Locale.Language {
        Locale.preferredLanguages.first.map(Locale.Language.init(identifier:)) ?? Locale.current.language
    }

    static func key(_ language: Locale.Language) -> String {
        let maximal = Locale.Language(identifier: language.maximalIdentifier)
        let code = maximal.languageCode?.identifier ?? language.minimalIdentifier
        guard code == "zh", let script = maximal.script?.identifier else { return code }
        return "\(code)-\(script)"
    }

    static func matches(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        key(lhs) == key(rhs)
    }

    static func name(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: key(language)) ?? language.minimalIdentifier
    }

    static func targets(
        for source: Locale.Language,
        preferring stored: String,
        preferred: [String] = Locale.preferredLanguages
    ) -> [Locale.Language] {
        let readable = preferred.map(Locale.Language.init(identifier:))
        guard !readable.contains(where: { matches($0, source) }) else { return [] }
        var seen = Set<String>()
        let candidates = (stored.isEmpty ? [] : [Locale.Language(identifier: stored)]) + readable
        return candidates.filter { !matches($0, source) && seen.insert(key($0)).inserted }
    }

    static func translatable(
        _ targets: [Locale.Language],
        from source: Locale.Language
    ) async -> [Locale.Language] {
        let availability = LanguageAvailability()
        var result: [Locale.Language] = []
        for target in targets where await availability.status(from: source, to: target) != .unsupported {
            result.append(target)
        }
        return result
    }

    @concurrent
    static func detectInBackground(_ sample: PageTranslationSample) async -> Locale.Language? {
        detect(sample)
    }

    static func detect(_ sample: PageTranslationSample) -> Locale.Language? {
        guard sample.text.count >= 24 else { return nil }
        let lines = sample.text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 24 }
        let recognizer = NLLanguageRecognizer()
        var votes: [NLLanguage: Double] = [:]
        for line in lines.isEmpty ? [sample.text] : lines {
            recognizer.reset()
            recognizer.processString(line)
            for (language, probability) in recognizer.languageHypotheses(withMaximum: 1) {
                votes[language, default: 0] += probability * Double(line.count)
            }
        }
        let total = votes.values.reduce(0, +)
        if let best = votes.max(by: { $0.value < $1.value }),
           best.key != .undetermined, total > 0, best.value / total >= 0.6 {
            return Locale.Language(identifier: best.key.rawValue)
        }
        guard sample.text.count >= 80 else { return nil }
        let declared = sample.declaredLanguage.trimmingCharacters(in: .whitespaces)
        guard !declared.isEmpty else { return nil }
        let language = Locale.Language(identifier: declared)
        return language.languageCode == nil ? nil : language
    }

    static func naturalLanguage(_ language: Locale.Language) -> NLLanguage {
        NLLanguage(rawValue: key(language))
    }

    nonisolated struct Skipper: Sendable {
        private let source: NLLanguage
        private let target: NLLanguage

        init(source: Locale.Language, target: Locale.Language) {
            self.source = TranslationLanguage.naturalLanguage(source)
            self.target = TranslationLanguage.naturalLanguage(target)
        }

        @concurrent
        func isAlreadyTarget(_ segments: [PageTranslationSegment]) async -> Bool {
            let text = segments.map(\.text).joined()
            guard text.count >= 16 else { return false }
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [source, target]
            recognizer.processString(text)
            return (recognizer.languageHypotheses(withMaximum: 2)[target] ?? 0) >= 0.8
        }
    }
}
