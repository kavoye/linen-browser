// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Observation
import WebKit

nonisolated struct PageWatch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    let condition: String
    let interval: TimeInterval
    let created: Date
    var nextCheck: Date
    var lastChecked: Date?
    var fingerprint: String?
    var snapshot: String?
    var state: String?
    var failures = 0

    static let intervals: ClosedRange<TimeInterval> = 300...86_400
    static let lifetime: TimeInterval = 30 * 86_400
    static let failureLimit = 3

    var expires: Date {
        created + Self.lifetime
    }

    var place: String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isSamePage(_ landed: URL, _ watched: URL) -> Bool {
        func path(_ url: URL) -> String {
            let path = url.path()
            return path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        func items(_ url: URL) -> Set<URLQueryItem> {
            Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        }
        return landed.host()?.lowercased() == watched.host()?.lowercased() && path(landed) == path(watched)
            && items(watched).isSubset(of: items(landed))
    }

    static func interval(minutes: Int) -> TimeInterval {
        min(max(TimeInterval(minutes) * 60, intervals.lowerBound), intervals.upperBound)
    }
}

nonisolated struct PageWatchReading: Equatable, Sendable {
    let title: String
    let text: String
    var url: URL?

    var fingerprint: String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct PageWatchChange: Equatable, Sendable {
    struct Pair: Equatable, Sendable {
        let removed: String?
        let added: String?
    }

    let removed: [String]
    let added: [String]
    private let removedAnchors: [Int]
    private let addedAnchors: [Int]

    var isEmpty: Bool {
        removed.isEmpty && added.isEmpty
    }

    var pairs: [Pair] {
        let anchors = Set(removedAnchors + addedAnchors).sorted()
        return anchors.flatMap { anchor in
            let gone = zip(removedAnchors, removed).filter { $0.0 == anchor }.map(\.1)
            let new = zip(addedAnchors, added).filter { $0.0 == anchor }.map(\.1)
            return (0..<max(gone.count, new.count)).map { index in
                Pair(
                    removed: index < gone.count ? gone[index] : nil,
                    added: index < new.count ? new[index] : nil
                )
            }
        }
    }

    init(removed: [String], added: [String]) {
        self.removed = removed
        self.added = added
        removedAnchors = Array(repeating: 0, count: removed.count)
        addedAnchors = Array(repeating: 0, count: added.count)
    }

    init(from old: String, to new: String) {
        let difference = Self.segments(in: new).difference(from: Self.segments(in: old))
        var removed: [String] = []
        var removedAnchors: [Int] = []
        for case .remove(let offset, let element, _) in difference.removals {
            removedAnchors.append(offset - removed.count)
            removed.append(element)
        }
        var added: [String] = []
        var addedAnchors: [Int] = []
        for case .insert(let offset, let element, _) in difference.insertions {
            addedAnchors.append(offset - added.count)
            added.append(element)
        }
        self.removed = removed
        self.added = added
        self.removedAnchors = removedAnchors
        self.addedAnchors = addedAnchors
    }

    static func segments(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).flatMap { sentences(in: String($0)) }
    }

    static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var ended = false
        for character in text {
            if ended, character.isWhitespace {
                sentences.append(current)
                current = ""
                ended = false
                continue
            }
            current.append(character)
            ended = ".!?…".contains(character)
        }
        sentences.append(current)
        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated struct PageWatchVerdict: Equatable, Sendable {
    let met: Bool
    let state: String
    let message: String
}

@MainActor
@Observable
final class PageWatchCenter {
    enum Notice: Equatable {
        case met(String)
        case unreachable
        case expired
    }

    enum Start: Equatable {
        case watching(PageWatch)
        case alreadyMet(PageWatchVerdict)
        case unreadable
        case noModel
    }

    private(set) var watches: [PageWatch] = [] {
        didSet {
            if watches.isEmpty != oldValue.isEmpty {
                onAvailabilityChange?(!watches.isEmpty)
            }
        }
    }

    @ObservationIgnored var onAvailabilityChange: ((Bool) -> Void)?

    @ObservationIgnored var fetch: (URL) async -> PageWatchReading?
    @ObservationIgnored var judge: (PageWatch, PageWatchReading) async -> PageWatchVerdict?
    @ObservationIgnored var classify: (PageWatch, PageWatchChange.Pair) async -> PageWatchVerdict?
    @ObservationIgnored var canJudge: () -> Bool
    @ObservationIgnored var notify: (PageWatch, Notice) -> Void
    @ObservationIgnored var allows: (URL) -> Bool
    @ObservationIgnored var now: () -> Date = Date.init

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let schedules: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var checking: Set<UUID> = []
    @ObservationIgnored private var isShutDown = false

    static let classifyLimit = 16

    init(
        file: URL?,
        schedules: Bool = true,
        fetch: @escaping (URL) async -> PageWatchReading?,
        judge: @escaping (PageWatch, PageWatchReading) async -> PageWatchVerdict?,
        classify: @escaping (PageWatch, PageWatchChange.Pair) async -> PageWatchVerdict?,
        canJudge: @escaping () -> Bool = { true },
        notify: @escaping (PageWatch, Notice) -> Void,
        allows: @escaping (URL) -> Bool = { _ in true }
    ) {
        self.file = file
        self.schedules = schedules
        self.fetch = fetch
        self.judge = judge
        self.classify = classify
        self.canJudge = canJudge
        self.notify = notify
        self.allows = allows
        if let file, let data = try? Data(contentsOf: file) {
            watches = (try? JSONDecoder().decode([PageWatch].self, from: data)) ?? []
        }
    }

    deinit {
        loop?.cancel()
        sleeper?.cancel()
    }

    func resume() {
        wake()
    }

    func start(url: URL, title: String, condition: String, everyMinutes minutes: Int) async -> Start {
        let date = now()
        var watch = PageWatch(
            id: UUID(),
            url: url,
            title: title,
            condition: condition,
            interval: PageWatch.interval(minutes: minutes),
            created: date,
            nextCheck: date
        )
        guard canJudge() else { return .noModel }
        guard let reading = await fetch(url), !reading.text.isEmpty else { return .unreadable }
        if let landed = reading.url, !PageWatch.isSamePage(landed, url) {
            return .unreadable
        }
        if !condition.isEmpty {
            guard let verdict = await judge(watch, reading) else { return .noModel }
            guard !verdict.met else { return .alreadyMet(verdict) }
            watch.state = verdict.state
        }
        if !reading.title.isEmpty {
            watch.title = reading.title
        }
        watch.fingerprint = reading.fingerprint
        watch.snapshot = reading.text
        watch.lastChecked = date
        watch.nextCheck = date + watch.interval
        watches.append(watch)
        save()
        wake()
        return .watching(watch)
    }

    @discardableResult
    func stop(_ id: UUID) -> PageWatch? {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = watches.remove(at: index)
        save()
        wake()
        return removed
    }

    func matching(_ reference: String) -> [PageWatch] {
        let needle = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return watches }
        if let id = UUID(uuidString: needle) {
            return watches.filter { $0.id == id }
        }
        return watches.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.url.absoluteString.localizedCaseInsensitiveContains(needle)
                || $0.condition.localizedCaseInsensitiveContains(needle)
        }
    }

    func checkDue() async {
        let date = now()
        let due = watches.filter { $0.nextCheck <= date }.sorted { $0.nextCheck < $1.nextCheck }
        for watch in due {
            await check(watch.id)
        }
    }

    func check(_ id: UUID) async {
        guard !checking.contains(id), let watch = watches.first(where: { $0.id == id }) else { return }
        checking.insert(id)
        defer { checking.remove(id) }

        guard now() < watch.expires else {
            finish(id, with: .expired)
            return
        }
        guard allows(watch.url) else {
            stop(id)
            return
        }
        guard let reading = await fetch(watch.url), !reading.text.isEmpty,
              reading.url.map({ PageWatch.isSamePage($0, watch.url) }) ?? true else {
            failed(id)
            return
        }
        let fingerprint = reading.fingerprint
        if fingerprint == watch.fingerprint {
            update(id) { $0.failures = 0 }
            return
        }
        guard let current = watches.first(where: { $0.id == id }) else { return }
        guard canJudge() else {
            postpone(id)
            return
        }
        let verdict: PageWatchVerdict
        if current.condition.isEmpty {
            let change = PageWatchChange(from: current.snapshot ?? reading.text, to: reading.text)
            guard let classified = await classify(change, for: current) else {
                postpone(id)
                return
            }
            verdict = classified
        } else if let judged = await judge(current, reading) {
            verdict = judged
        } else {
            postpone(id)
            return
        }
        guard watches.contains(where: { $0.id == id }) else { return }
        if verdict.met {
            finish(id, with: .met(verdict.message))
            return
        }
        update(id) {
            $0.failures = 0
            $0.fingerprint = fingerprint
            $0.snapshot = reading.text
            if !verdict.state.isEmpty {
                $0.state = verdict.state
            }
            if !reading.title.isEmpty {
                $0.title = reading.title
            }
        }
    }

    private func classify(_ change: PageWatchChange, for watch: PageWatch) async -> PageWatchVerdict? {
        let pairs = change.pairs
        for pair in pairs.prefix(Self.classifyLimit) {
            guard let verdict = await classify(watch, pair) else { return nil }
            if verdict.met {
                return verdict
            }
        }
        return PageWatchVerdict(met: false, state: "", message: "")
    }

    private func failed(_ id: UUID) {
        guard let watch = watches.first(where: { $0.id == id }) else { return }
        guard watch.failures + 1 < PageWatch.failureLimit else {
            finish(id, with: .unreachable)
            return
        }
        update(id) { $0.failures += 1 }
    }

    private func postpone(_ id: UUID) {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
        watches[index].nextCheck = now() + watches[index].interval
        save()
    }

    private func finish(_ id: UUID, with notice: Notice) {
        guard let watch = stop(id) else { return }
        notify(watch, notice)
    }

    private func update(_ id: UUID, _ change: (inout PageWatch) -> Void) {
        guard let index = watches.firstIndex(where: { $0.id == id }) else { return }
        let date = now()
        change(&watches[index])
        watches[index].lastChecked = date
        watches[index].nextCheck = date + watches[index].interval
        save()
    }

    private func save() {
        guard let file, !isShutDown else { return }
        let snapshot = watches
        Task { await JSONFileStore.shared.write(snapshot, to: file) }
    }

    // MARK: - Schedule

    private func wake() {
        guard schedules, !isShutDown else { return }
        if let loop, !loop.isCancelled {
            sleeper?.cancel()
            return
        }
        guard !watches.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled, let nap = self?.napUntilNextCheck() {
                await nap.value
                guard !Task.isCancelled, let self else { break }
                sleeper = nil
                await checkDue()
            }
            self?.loop = nil
        }
    }

    private func napUntilNextCheck() -> Task<Void, Never>? {
        guard let next = watches.map(\.nextCheck).min() else { return nil }
        let delay = min(max(next.timeIntervalSince(now()), 0), 900)
        let nap = Task<Void, Never> {
            guard delay > 0 else { return }
            try? await Task.sleep(for: .seconds(delay))
        }
        sleeper = nap
        return nap
    }

    func shutDown() {
        isShutDown = true
        watches = []
        loop?.cancel()
        sleeper?.cancel()
        loop = nil
    }
}

// MARK: - Live

extension PageWatchCenter {
    static func live(for context: BrowserProfileContext) -> PageWatchCenter {
        let persists = !context.profile.isPrivate && !AppDatabase.isRunningTests && AppDatabase.ownsSession
        let dataStore = context.dataStore
        let permissions = context.sitePermissions
        let profileID = context.profile.id
        return PageWatchCenter(
            file: persists ? context.profile.pageWatchesFile : nil,
            schedules: persists,
            fetch: { url in await PageWatchLoader.read(url, dataStore: dataStore) },
            judge: { watch, reading in await PageWatchJudge.judge(watch, reading: reading) },
            classify: { _, pair in await PageWatchJudge.classify(pair) },
            canJudge: { UtilityModelSource.isAvailable },
            notify: { watch, notice in NotificationBridge.shared.announce(watch, notice, profileID: profileID) },
            allows: { url in permissions.assistantAccess(for: SitePermissions.origin(for: url)) != .deny }
        )
    }
}

extension Profile {
    var pageWatchesFile: URL {
        supportDirectory.appendingPathComponent("PageWatches.json")
    }
}

@MainActor
enum PageWatchLoader {
    private static let loadCeiling: Duration = .seconds(15)
    private static let quietCeiling: Duration = .seconds(2)

    static func canWatch(_ url: URL) -> Bool {
        LinkPeekLoader.canPeek(url)
    }

    static func read(_ url: URL, dataStore: WKWebsiteDataStore) async -> PageWatchReading? {
        guard canWatch(url) else { return nil }
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = dataStore
        BrowserSettings.shared.apply(to: configuration)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720), configuration: configuration)
        BrowserSettings.shared.apply(to: view)
        view.customUserAgent = WebViewPool.safariUserAgent
        defer {
            view.stopLoading()
        }
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        await PageSettle.untilIdle(view, timeout: loadCeiling)
        await PageSettle.untilQuiet(view, ceiling: quietCeiling)
        guard !Task.isCancelled,
              let landed = view.url, canWatch(landed),
              let value = try? await view.evaluateJavaScript(script) as? String,
              view.url == landed,
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["challenge"] as? Bool != true
        else { return nil }
        return PageWatchReading(
            title: object["title"] as? String ?? "",
            text: String((object["text"] as? String ?? "").prefix(LinkPeekLoader.textBudget)),
            url: landed
        )
    }

    private static let script = #"""
    (() => {
      const root = document.querySelector('article')
        || document.querySelector('main')
        || document.querySelector('[role="main"]')
        || document.body;
      const lines = node => (node ? node.innerText : '')
        .split('\n')
        .map(line => line.replace(/\s+/g, ' ').trim())
        .filter(line => line.length > 0);
      let text = lines(root);
      if (text.join(' ').length < 240) text = lines(document.body);
      const challenge = !!document.querySelector(
        '#challenge-form, #challenge-running, #cf-challenge-running, .cf-browser-verification, [name="cf-turnstile-response"]'
      );
      return JSON.stringify({
        title: (document.title || '').replace(/\s+/g, ' ').trim(),
        text: text.join('\n').slice(0, 6000),
        challenge: challenge
      });
    })()
    """#
}
