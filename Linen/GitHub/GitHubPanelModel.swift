// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class GitHubPanelModel {
    private(set) var account: GitHubAccount? {
        didSet { rebuildSections() }
    }
    private(set) var pullRequests: [GitHubInboxPR] = []
    private(set) var triage = GitHubTriage() {
        didSet { rebuildSections() }
    }
    private(set) var notifications: [GitHubNotification] = [] {
        didSet { rebuildSections() }
    }
    private(set) var sections: [GitHubInboxSection] = []
    private(set) var filters: [GitHubFilter]
    private(set) var selectedFilterID: String
    private(set) var hasConnection = false
    private(set) var needsReconnect = false
    private(set) var isRefreshing = false
    private(set) var isConnecting = false
    private(set) var isLoadingMore = false
    private(set) var deviceCode: GitHubDeviceCode?
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private(set) var retryAfter: Date? {
        didSet { scheduleThrottleEnd() }
    }
    private(set) var totalPRs = 0
    private(set) var nextCursor: String?
    private(set) var hasMoreNotifications = false
    private(set) var markingRead: Set<String> = []
    private(set) var hasPrivateAccess: Bool?
    private(set) var hasOrgAccess: Bool?
    private var notifies: Bool
    @ObservationIgnored var announce: (@MainActor (GitHubPRUpdate) -> Void)?
    private(set) var requiresSSO = false
    let isPrivate: Bool
    let isConfigured: Bool
    private(set) var selectedItemID: String?
    private(set) var selectedPR: GitHubInboxPR?
    private(set) var details: [String: GitHubPRDetails] = [:]
    private(set) var looked: [String: GitHubInboxPR] = [:]
    private(set) var detailErrors: [String: String] = [:]
    private(set) var loadingDetails: Set<String> = []
    private(set) var threads: [String: GitHubThreadLoad] = [:]

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private let authorization: GitHubAuthorization
    @ObservationIgnored private let store: GitHubConnectionStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var authGeneration = 0
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pollInterval: TimeInterval = 60
    @ObservationIgnored private var notificationPage = 1
    @ObservationIgnored private var readThreadUpdates: [String: Date] = [:]
    @ObservationIgnored private var detailVersions: [String: String] = [:]
    @ObservationIgnored private var snapshots: [String: GitHubPRSnapshot]?
    @ObservationIgnored private var activitySince: Date?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var pagingTask: Task<Void, Never>?
    @ObservationIgnored private var throttleTask: Task<Void, Never>?
    @ObservationIgnored private var detailTasks: [String: Task<GitHubPRDetails?, Never>] = [:]
    @ObservationIgnored private var threadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var threadVersions: [String: Date] = [:]
    @ObservationIgnored private var lookedAt: [String: Date] = [:]
    @ObservationIgnored private var triageFetchedAt: Date?
    @ObservationIgnored private var filterFetchedAt: Date?
    @ObservationIgnored private var notificationsModified: String?
    @ObservationIgnored private var pageGeneration = 0
    @ObservationIgnored private var pullRequestPages = 1
    @ObservationIgnored private var firstPagePRs: Set<String> = []
    @ObservationIgnored private var firstPageNotifications: Set<String> = []
    @ObservationIgnored private var visiblePanels = 0
    @ObservationIgnored private var rateLimitStrikes = 0
    @ObservationIgnored private var runningScope: RefreshScope?

    private enum RefreshScope {
        case full, filter, background
    }

    init(
        profileID: UUID, isPrivate: Bool = false, defaults: UserDefaults,
        client: GitHubClient = GitHubClient(), authorization: GitHubAuthorization = GitHubAuthorization(),
        storage: CredentialStore.Storage = .keychain,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.isPrivate = isPrivate
        self.defaults = defaults
        self.client = client
        self.authorization = authorization
        self.store = GitHubConnectionStore(profileID: profileID, storage: storage)
        self.sleep = sleep
        isConfigured = !authorization.clientID.isEmpty
        let saved = isPrivate ? nil : defaults.data(forKey: "github.filters")
        let restored = saved.flatMap { try? JSONDecoder().decode([GitHubFilter].self, from: $0) }
        let initialFilters = restored?.isEmpty == false ? restored! : GitHubFilter.defaults
        notifies = isPrivate ? false : defaults.object(forKey: "github.notifiesAboutPullRequests") as? Bool ?? true
        if !isPrivate {
            snapshots = defaults.data(forKey: "github.pullRequestSnapshots")
                .flatMap { try? JSONDecoder().decode([String: GitHubPRSnapshot].self, from: $0) }
            activitySince = defaults.object(forKey: "github.activitySince") as? Date
        }
        filters = initialFilters
        let selected = isPrivate ? nil : defaults.string(forKey: "github.selectedFilter")
        selectedFilterID = initialFilters.first(where: { $0.id == selected })?.id ?? GitHubFilter.inboxID
    }

    deinit {
        monitorTask?.cancel()
        loadTask?.cancel()
        authTask?.cancel()
        pagingTask?.cancel()
        throttleTask?.cancel()
        detailTasks.values.forEach { $0.cancel() }
        threadTasks.values.forEach { $0.cancel() }
    }

    var selectedFilter: GitHubFilter {
        filters.first { $0.id == selectedFilterID } ?? filters[0]
    }

    var isInbox: Bool {
        selectedFilterID == GitHubFilter.inboxID
    }

    private func rebuildSections() {
        let rebuilt = GitHubInboxSection.build(triage: triage, notifications: notifications, login: account?.login)
        if rebuilt != sections {
            sections = rebuilt
        }
    }

    func select(_ item: GitHubInboxItem, open: (URL) -> Void) {
        if let notification = item.notification {
            markRead(notification)
        }
        guard let pr = item.pr else {
            if let url = item.url {
                open(url)
            }
            return
        }
        selectedItemID = item.id
        selectedPR = pr
        loadDetails(for: pr)
    }

    func select(_ pr: GitHubInboxPR) {
        selectedItemID = pr.id
        selectedPR = pr
        loadDetails(for: pr)
    }

    var canPreview: Bool {
        !isPrivate && token != nil && hasConnection && !needsReconnect
    }

    var notifiesAboutPullRequests: Bool {
        get { notifies }
        set { setNotifiesAboutPullRequests(newValue) }
    }

    var isRateLimited: Bool {
        retryAfter != nil
    }

    private var isThrottled: Bool {
        retryAfter.map { $0 > .now } ?? false
    }

    private func scheduleThrottleEnd() {
        throttleTask?.cancel()
        guard let deadline = retryAfter else { return }
        let sleep = sleep
        throttleTask = Task { [weak self] in
            try? await sleep(.seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, retryAfter == deadline else { return }
            retryAfter = nil
        }
    }

    private var freshness: TimeInterval {
        max(60, pollInterval)
    }

    private func isFresh(_ date: Date?) -> Bool {
        date.map { Date.now.timeIntervalSince($0) < freshness } ?? false
    }

    private func known(_ key: String) -> (pr: GitHubInboxPR, fetchedAt: Date?)? {
        let candidates: [(pr: GitHubInboxPR, fetchedAt: Date?)] = [
            triage.all.first { $0.key == key }.map { ($0, triageFetchedAt) },
            pullRequests.first { $0.key == key }.map { ($0, filterFetchedAt) },
            looked[key].map { ($0, lookedAt[key]) },
        ].compactMap { $0 }
        return candidates.max { ($0.fetchedAt ?? .distantPast) < ($1.fetchedAt ?? .distantPast) }
    }

    private func lookUp(_ reference: GitHubPullRequestReference, token: String) async -> GitHubInboxPR? {
        if let cached = known(reference.key), isFresh(cached.fetchedAt) {
            return cached.pr
        }
        guard !isThrottled else { return known(reference.key)?.pr }
        let connection = connectionGeneration
        do {
            let pr = try await client.pullRequest(reference, token: token)
            guard connection == connectionGeneration else { return nil }
            looked[pr.key] = pr
            lookedAt[pr.key] = .now
            return pr
        } catch {
            guard connection == connectionGeneration else { return nil }
            if case GitHubFailure.unauthorized = error {
                handle(error)
            } else if case GitHubFailure.rateLimited = error {
                handle(error)
            }
            return known(reference.key)?.pr
        }
    }

    func preview(_ reference: GitHubPullRequestReference) async -> (pr: GitHubInboxPR, details: GitHubPRDetails?)? {
        guard canPreview, let token else { return nil }
        let connection = connectionGeneration
        guard let pr = await lookUp(reference, token: token), connection == connectionGeneration else { return nil }
        let loaded = await fetchDetails(for: pr)?.value ?? details[pr.id]
        guard connection == connectionGeneration else { return nil }
        return (pr, loaded)
    }

    var knownRepositories: [String] {
        var seen: Set<String> = []
        let names = (triage.authored + triage.reviewRequested).map(\.repository.nameWithOwner)
            + notifications.map(\.repository.fullName)
            + (triage.recent + pullRequests).map(\.repository.nameWithOwner)
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    func paletteSearch(_ query: String) async -> [GitHubSearchHit]? {
        guard canPreview, !isThrottled, let token, let login = account?.login else { return nil }
        let connection = connectionGeneration
        do {
            return try await client.paletteSearch(query, login: login, repositories: knownRepositories, token: token)
        } catch {
            guard connection == connectionGeneration else { return nil }
            if case GitHubFailure.unauthorized = error {
                handle(error)
            } else if case GitHubFailure.rateLimited = error {
                handle(error)
            }
            return nil
        }
    }

    func matchCount(for query: String) async throws -> Int? {
        guard canPreview, !isThrottled, let token, let login = account?.login else { return nil }
        return try await client.matchCount(query: GitHubFilter(id: "", name: "", query: query).searchQuery(login: login), token: token)
    }

    func cachedPreview(_ reference: GitHubPullRequestReference) -> (pr: GitHubInboxPR, details: GitHubPRDetails?)? {
        guard let pr = known(reference.key)?.pr else { return nil }
        return (pr, details[pr.id])
    }

    func refreshPreview(_ reference: GitHubPullRequestReference) async {
        guard canPreview, let token else { return }
        let connection = connectionGeneration
        guard let pr = await lookUp(reference, token: token), connection == connectionGeneration else { return }
        loadDetails(for: pr)
    }

    func loadDetails(for pr: GitHubInboxPR, force: Bool = false) {
        fetchDetails(for: pr, force: force)
    }

    func loadPreview(for item: GitHubInboxItem) {
        if let pr = item.pr {
            loadDetails(for: pr)
        }
        if item.showsThread, let notification = item.notification {
            loadThread(for: notification)
        }
    }

    func thread(for item: GitHubInboxItem) -> GitHubThreadLoad? {
        guard item.showsThread, let notification = item.notification else { return nil }
        return threads[notification.id] ?? .loading
    }

    private func loadThread(for notification: GitHubNotification) {
        let id = notification.id
        guard threadTasks[id] == nil else { return }
        if case .loaded = threads[id], threadVersions[id] == notification.updatedAt {
            return
        }
        guard let token, let subject = notification.thread, !needsReconnect, !isThrottled else {
            threads[id] = threads[id] ?? .failed
            return
        }
        if threads[id] == .failed {
            threads[id] = nil
        }
        let connection = connectionGeneration
        threadTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if connection == connectionGeneration {
                    threadTasks[id] = nil
                }
            }
            do {
                let loaded = try await client.thread(subject, token: token)
                guard connection == connectionGeneration else { return }
                threads[id] = .loaded(loaded)
                threadVersions[id] = notification.updatedAt
            } catch {
                guard connection == connectionGeneration else { return }
                if threads[id] == nil {
                    threads[id] = .failed
                }
                if case GitHubFailure.unauthorized = error {
                    handle(error)
                } else if case GitHubFailure.rateLimited = error {
                    handle(error)
                }
            }
        }
    }

    @discardableResult
    private func fetchDetails(for pr: GitHubInboxPR, force: Bool = false) -> Task<GitHubPRDetails?, Never>? {
        guard let token, let reference = pr.reference, !needsReconnect else { return nil }
        if let running = detailTasks[pr.id] {
            return running
        }
        let includeTeams = hasOrgAccess == true
        let version = "\(pr.updatedAt.timeIntervalSince1970)|\(pr.checks ?? "")|\(pr.mergeable)|\(includeTeams)"
        if !force, details[pr.id] != nil, detailVersions[pr.id] == version {
            return nil
        }
        guard !isThrottled else { return nil }
        loadingDetails.insert(pr.id)
        detailErrors[pr.id] = nil
        let connection = connectionGeneration
        let task = Task { [weak self] () -> GitHubPRDetails? in
            guard let self else { return nil }
            defer {
                if connection == connectionGeneration {
                    loadingDetails.remove(pr.id)
                    detailTasks[pr.id] = nil
                }
            }
            do {
                let loaded = try await client.pullRequestDetails(reference, includeTeams: includeTeams, token: token)
                guard connection == connectionGeneration else { return nil }
                details[pr.id] = loaded
                detailVersions[pr.id] = version
                return loaded
            } catch {
                guard connection == connectionGeneration else { return nil }
                detailErrors[pr.id] = error.localizedDescription
                if case GitHubFailure.unauthorized = error {
                    handle(error)
                } else if case GitHubFailure.rateLimited = error {
                    handle(error)
                }
                return nil
            }
        }
        detailTasks[pr.id] = task
        return task
    }

    func clearSelection() {
        selectedItemID = nil
        selectedPR = nil
    }

    func start() {
        guard !started, !isPrivate else { return }
        started = true
        token = store.read()
        hasConnection = token?.isEmpty == false
        if hasConnection {
            beginMonitoring()
        }
    }

    func panelDidAppear() {
        visiblePanels += 1
        guard visiblePanels == 1, runningScope != .full,
              !isFresh(triageFetchedAt) || (!isInbox && !isFresh(filterFetchedAt)) else { return }
        refresh(.full)
    }

    func panelDidDisappear() {
        visiblePanels = max(0, visiblePanels - 1)
    }

    func setNotifiesAboutPullRequests(_ value: Bool) {
        guard !isPrivate else { return }
        if value, !notifies {
            forgetSnapshots()
        }
        notifies = value
        defaults.set(value, forKey: "github.notifiesAboutPullRequests")
    }

    private func announceChanges(authored: [GitHubInboxPR], notifications items: [GitHubNotification], fetchedAt: Date) {
        guard !isPrivate else { return }
        let since = activitySince
        let activity = Set(items.filter { item in
            since.map { item.updatedAt > $0 } ?? false && item.reason != "ci_activity"
        }.compactMap(\.key))
        if let snapshots, notifiesAboutPullRequests {
            for update in GitHubPRUpdate.changes(
                previous: snapshots, authored: authored, activity: activity, login: account?.login
            ) {
                announce?(update)
            }
        }
        let next = Dictionary(authored.map { ($0.id, GitHubPRSnapshot($0)) }, uniquingKeysWith: { first, _ in first })
        snapshots = next
        activitySince = max(since ?? fetchedAt, items.map(\.updatedAt).max() ?? fetchedAt)
        defaults.set(try? JSONEncoder().encode(next), forKey: "github.pullRequestSnapshots")
        defaults.set(activitySince, forKey: "github.activitySince")
    }

    private func forgetSnapshots() {
        snapshots = nil
        activitySince = nil
        defaults.removeObject(forKey: "github.pullRequestSnapshots")
        defaults.removeObject(forKey: "github.activitySince")
    }

    func selectFilter(_ id: String) {
        guard id == GitHubFilter.inboxID || filters.contains(where: { $0.id == id }), selectedFilterID != id else { return }
        selectedFilterID = id
        clearSelection()
        resetFilterResults()
        persistFilters()
        refreshFilter()
    }

    func saveFilter(_ filter: GitHubFilter) {
        let name = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !query.isEmpty, query.count <= 1000 else { return }
        let updated = GitHubFilter(id: filter.id, name: name, query: query, symbol: filter.symbol)
        if let index = filters.firstIndex(where: { $0.id == filter.id }) {
            filters[index] = updated
        } else {
            filters.append(updated)
        }
        selectedFilterID = updated.id
        clearSelection()
        resetFilterResults()
        persistFilters()
        refreshFilter()
    }

    func deleteFilter(_ id: String) {
        guard id != GitHubFilter.inboxID, filters.count > 1, filters.contains(where: { $0.id == id }) else { return }
        filters.removeAll { $0.id == id }
        guard selectedFilterID == id else {
            persistFilters()
            return
        }
        selectedFilterID = GitHubFilter.inboxID
        clearSelection()
        resetFilterResults()
        persistFilters()
        refreshFilter()
    }

    private func resetFilterResults() {
        pageGeneration += 1
        pagingTask?.cancel()
        isLoadingMore = false
        pullRequests = []
        nextCursor = nil
        totalPRs = 0
        pullRequestPages = 1
        firstPagePRs = []
        filterFetchedAt = nil
    }

    private func refreshFilter() {
        if !isInbox {
            refresh(.filter)
        } else if !isFresh(triageFetchedAt) {
            refresh(.full)
        }
    }

    private func persistFilters() {
        guard !isPrivate else { return }
        defaults.set(try? JSONEncoder().encode(filters), forKey: "github.filters")
        defaults.set(selectedFilterID, forKey: "github.selectedFilter")
    }

    func connect(includePrivate: Bool, open: @escaping @MainActor (URL) -> Void) {
        guard !isPrivate, !isConnecting else { return }
        cancelSignIn()
        isConnecting = true
        errorMessage = nil
        let attempt = authGeneration
        authTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if attempt == authGeneration {
                    isConnecting = false
                    deviceCode = nil
                }
            }
            do {
                let code = try await authorization.begin(includePrivate: includePrivate)
                guard attempt == authGeneration, !Task.isCancelled else { return }
                deviceCode = code
                open(code.verificationUri)
                let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))
                var interval = max(5, code.interval)
                while Date.now < deadline {
                    try await sleep(.seconds(interval))
                    try Task.checkCancellation()
                    guard Date.now < deadline else { throw GitHubFailure.expired }
                    let result = try await authorization.poll(code)
                    guard attempt == authGeneration, !Task.isCancelled else { return }
                    switch result {
                    case .pending:
                        continue
                    case .slowDown:
                        interval += 5
                    case .authorized(let credential):
                        let user = try await client.account(token: credential)
                        guard attempt == authGeneration, !Task.isCancelled else { return }
                        try store.save(credential)
                        resetData()
                        forgetSnapshots()
                        token = credential
                        account = user
                        started = true
                        hasConnection = true
                        needsReconnect = false
                        beginMonitoring()
                        return
                    }
                }
                throw GitHubFailure.expired
            } catch {
                if attempt == authGeneration, !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelSignIn() {
        authGeneration += 1
        authTask?.cancel()
        authTask = nil
        isConnecting = false
        deviceCode = nil
    }

    func disconnect() {
        do {
            try store.save(nil)
            stop()
            forgetSnapshots()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        cancelSignIn()
        resetData()
        token = nil
        account = nil
        hasConnection = false
        needsReconnect = false
        started = false
    }

    private func resetData() {
        generation += 1
        connectionGeneration += 1
        monitorTask?.cancel()
        loadTask?.cancel()
        pagingTask?.cancel()
        monitorTask = nil
        pullRequests = []
        triage = GitHubTriage()
        details = [:]
        looked = [:]
        detailErrors = [:]
        detailVersions = [:]
        loadingDetails = []
        detailTasks.values.forEach { $0.cancel() }
        detailTasks = [:]
        threads = [:]
        threadVersions = [:]
        threadTasks.values.forEach { $0.cancel() }
        threadTasks = [:]
        lookedAt = [:]
        triageFetchedAt = nil
        filterFetchedAt = nil
        notificationsModified = nil
        pageGeneration += 1
        pullRequestPages = 1
        firstPagePRs = []
        firstPageNotifications = []
        notificationPage = 1
        rateLimitStrikes = 0
        clearSelection()
        notifications = []
        readThreadUpdates = [:]
        markingRead = []
        hasPrivateAccess = nil
        hasOrgAccess = nil
        requiresSSO = false
        nextCursor = nil
        totalPRs = 0
        lastUpdated = nil
        retryAfter = nil
        hasMoreNotifications = false
        isRefreshing = false
        runningScope = nil
        isLoadingMore = false
    }

    private func beginMonitoring() {
        monitorTask?.cancel()
        refresh(.full)
        let sleep = sleep
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? 60
                do { try await sleep(.seconds(interval)) } catch { return }
                guard !Task.isCancelled, self != nil else { return }
                self?.refresh()
            }
        }
    }

    func refresh() {
        refresh(visiblePanels > 0 ? .full : .background)
    }

    private static func merged(_ requested: RefreshScope, into running: RefreshScope?) -> RefreshScope? {
        switch (running, requested) {
        case (nil, _):
            requested
        case (_, .background):
            nil
        case (.filter?, .filter):
            .filter
        default:
            .full
        }
    }

    private func refresh(_ requested: RefreshScope) {
        guard !isPrivate, let token, !needsReconnect, !isThrottled,
              let scope = Self.merged(requested, into: runningScope) else { return }
        generation += 1
        let request = generation
        let pages = pageGeneration
        loadTask?.cancel()
        isRefreshing = true
        runningScope = scope
        let filter = scope == .background || isInbox ? nil : selectedFilter
        let knownRepositories = triage.authored.map(\.repository.nameWithOwner)
        let covered = Set((triage.reviewRequested + triage.authored).map(\.key))
        let modified = notificationsModified
        let wantsNotifications = scope != .filter
        let wantsTriage = scope == .full
        let wantsAuthored = scope == .background && notifiesAboutPullRequests
        let fetchedAt = Date.now
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if request == generation {
                    isRefreshing = false
                    runningScope = nil
                }
            }
            do {
                let user: GitHubAccount
                if let account {
                    user = account
                } else {
                    user = try await client.account(token: token)
                }
                guard request == generation, !Task.isCancelled else { return }
                account = user
                var inboxResult: Result<GitHubNotificationPage, Error>?
                if wantsNotifications {
                    inboxResult = await Self.result { try await self.client.notifications(since: modified, token: token) }
                }
                let changed = inboxResult.flatMap { try? $0.get() }.flatMap { $0.isUnchanged ? nil : $0.items }
                let items = changed ?? notifications
                let repositories = items.map(\.repository.fullName) + knownRepositories
                let related = items.compactMap(\.reference).filter { !covered.contains($0.key) }
                async let triageCall: Result<GitHubTriage, Error>? = wantsTriage ? await Self.result {
                    try await self.client.triage(login: user.login, repositories: repositories, related: related, token: token)
                } : nil
                async let authoredCall: Result<[GitHubInboxPR], Error>? = wantsAuthored ? await Self.result {
                    try await self.client.authoredPullRequests(login: user.login, token: token)
                } : nil
                var prResult: Result<GitHubPRPage, Error>?
                if let filter {
                    prResult = await Self.result { try await self.client.pullRequests(query: filter.searchQuery(login: user.login), token: token) }
                }
                let triageResult = await triageCall
                let authoredResult = await authoredCall
                guard request == generation, !Task.isCancelled else { return }
                errorMessage = nil
                retryAfter = isThrottled ? retryAfter : nil
                apply(prResult, pages: pages, fetchedAt: fetchedAt)
                let authored = apply(triage: triageResult, authored: authoredResult, fetchedAt: fetchedAt)
                if let selected = selectedPR, let fresh = (pullRequests + triage.all).first(where: { $0.id == selected.id }) {
                    selectedPR = fresh
                    loadDetails(for: fresh)
                }
                apply(inboxResult)
                if let authored, case .success(let page) = inboxResult {
                    announceChanges(authored: authored, notifications: page.isUnchanged ? [] : page.items, fetchedAt: fetchedAt)
                }
                if errorMessage == nil {
                    lastUpdated = .now
                    rateLimitStrikes = 0
                }
            } catch {
                if request == generation, !Task.isCancelled {
                    handle(error)
                }
            }
        }
    }

    func loadMore(notifications showNotifications: Bool) {
        guard !isRefreshing, !isLoadingMore, let token, let account, !needsReconnect, !isThrottled else { return }
        guard showNotifications ? hasMoreNotifications : nextCursor != nil else { return }
        isLoadingMore = true
        let request = pageGeneration
        pagingTask = Task { [weak self] in
            guard let self else { return }
            defer { if request == pageGeneration { isLoadingMore = false } }
            do {
                if showNotifications {
                    let oldest = notifications.map(\.updatedAt).min()
                    let page = try await client.notifications(before: oldest?.addingTimeInterval(1), token: token)
                    guard request == pageGeneration, !Task.isCancelled else { return }
                    let ids = Set(notifications.map(\.id))
                    notifications += page.items.filter {
                        !ids.contains($0.id) && $0.updatedAt > (readThreadUpdates[$0.id] ?? .distantPast)
                    }
                    notificationPage += 1
                    hasMoreNotifications = page.hasMore
                } else {
                    let page = try await client.pullRequests(query: selectedFilter.searchQuery(login: account.login), cursor: nextCursor, token: token)
                    guard request == pageGeneration, !Task.isCancelled else { return }
                    let ids = Set(pullRequests.map(\.id))
                    pullRequests += page.items.filter { !ids.contains($0.id) }
                    pullRequestPages += 1
                    nextCursor = page.cursor
                }
            } catch {
                if request == pageGeneration, !Task.isCancelled {
                    handle(error)
                }
            }
        }
    }

    func markRead(_ notification: GitHubNotification) {
        guard let token, !needsReconnect, !isThrottled, !markingRead.contains(notification.id) else { return }
        markingRead.insert(notification.id)
        let connection = connectionGeneration
        Task { [weak self] in
            guard let self else { return }
            defer {
                if connection == connectionGeneration {
                    markingRead.remove(notification.id)
                }
            }
            do {
                try await client.markRead(id: notification.id, token: token)
                guard connection == connectionGeneration else { return }
                readThreadUpdates[notification.id] = notification.updatedAt
                notifications.removeAll { $0.id == notification.id && $0.updatedAt <= notification.updatedAt }
            } catch {
                if connection == connectionGeneration {
                    handle(error)
                }
            }
        }
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
        if case GitHubFailure.unauthorized = error {
            needsReconnect = true
            monitorTask?.cancel()
        }
        if case GitHubFailure.rateLimited(let date) = error {
            rateLimitStrikes += isThrottled ? 0 : 1
            let backoff = min(900, 60 * pow(2, Double(min(rateLimitStrikes, 5) - 1)))
            retryAfter = max(retryAfter ?? date, date, .now.addingTimeInterval(backoff))
        }
    }

    private nonisolated static func result<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
}

private extension GitHubPanelModel {
    func apply(_ result: Result<GitHubPRPage, Error>?, pages: Int, fetchedAt: Date) {
        switch result {
        case .success(let page) where pages == pageGeneration:
            pullRequests = Self.merge(page.items, into: pullRequests, firstPage: firstPagePRs, keepsMore: pullRequestPages > 1)
            firstPagePRs = Set(page.items.map(\.id))
            totalPRs = page.total
            if pullRequestPages == 1 {
                nextCursor = page.cursor
            }
            filterFetchedAt = fetchedAt
        case .failure(let error):
            handle(error)
        default:
            break
        }
    }

    func apply(
        triage triageResult: Result<GitHubTriage, Error>?, authored authoredResult: Result<[GitHubInboxPR], Error>?, fetchedAt: Date
    ) -> [GitHubInboxPR]? {
        var authored: [GitHubInboxPR]?
        switch triageResult {
        case .success(let value):
            triage = value
            triageFetchedAt = fetchedAt
            authored = value.authored
        case .failure(let error):
            handle(error)
        case nil:
            break
        }
        switch authoredResult {
        case .success(let value):
            triage.authored = value
            authored = value
        case .failure(let error):
            handle(error)
        case nil:
            break
        }
        return authored
    }

    func apply(_ result: Result<GitHubNotificationPage, Error>?) {
        switch result {
        case .success(let page):
            pollInterval = page.pollInterval
            guard !page.isUnchanged else { return }
            let unread = page.items.filter { $0.updatedAt > (readThreadUpdates[$0.id] ?? .distantPast) }
            notifications = Self.merge(unread, into: notifications, firstPage: firstPageNotifications, keepsMore: notificationPage > 1)
            firstPageNotifications = Set(page.items.map(\.id))
            if notificationPage == 1 {
                hasMoreNotifications = page.hasMore
            }
            notificationsModified = page.lastModified
            hasPrivateAccess = page.scopes.map { $0.contains("repo") }
            hasOrgAccess = page.scopes.map { !$0.isDisjoint(with: ["read:org", "write:org", "admin:org"]) }
            requiresSSO = page.requiresSSO
        case .failure(let error):
            handle(error)
        case nil:
            break
        }
    }

    static func merge<Item: Identifiable>(
        _ fresh: [Item], into loaded: [Item], firstPage: Set<Item.ID>, keepsMore: Bool
    ) -> [Item] {
        guard keepsMore else { return fresh }
        let ids = Set(fresh.map(\.id))
        return fresh + loaded.filter { !ids.contains($0.id) && !firstPage.contains($0.id) }
    }
}
