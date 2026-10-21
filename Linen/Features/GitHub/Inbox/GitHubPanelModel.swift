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
    private(set) var triage = GitHubTriage() {
        didSet { rebuildSections() }
    }
    private(set) var pages = GitHubInboxPages() {
        didSet {
            if pages.notifications != oldValue.notifications {
                rebuildSections()
            }
        }
    }
    private(set) var sections: [GitHubInboxSection] = []
    private(set) var filterBook: GitHubFilterBook
    private(set) var hasConnection = false
    private(set) var needsReconnect = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?
    private var rateLimit = GitHubRateLimit() {
        didSet { scheduleThrottleEnd() }
    }
    private(set) var markingRead: Set<String> = []
    private(set) var hasPrivateAccess: Bool?
    private(set) var hasOrgAccess: Bool?
    private var activity: GitHubActivityMemory
    @ObservationIgnored var announce: (@MainActor (GitHubPRUpdate) -> Void)?
    private(set) var requiresSSO = false
    let isPrivate: Bool
    let isConfigured: Bool
    private(set) var selectedItemID: String?
    private(set) var selectedPR: GitHubInboxPR?
    let previews: GitHubPreviewLoader
    let signIn: GitHubSignIn

    @ObservationIgnored private let client: GitHubClient
    @ObservationIgnored private let store: GitHubConnectionStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pollInterval: TimeInterval = 60
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pagingTask: Task<Void, Never>?
    @ObservationIgnored private var throttleTask: Task<Void, Never>?
    @ObservationIgnored private var triageFetchedAt: Date?
    @ObservationIgnored private var filterFetchedAt: Date?
    @ObservationIgnored private var visiblePanels = 0
    @ObservationIgnored private var runningScope: GitHubRefreshScope?

    init(
        profileID: UUID, isPrivate: Bool = false, defaults: UserDefaults,
        client: GitHubClient = GitHubClient(), authorization: GitHubAuthorization = GitHubAuthorization(),
        storage: CredentialStore.Storage = .keychain,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.isPrivate = isPrivate
        self.defaults = defaults
        self.client = client
        self.store = GitHubConnectionStore(profileID: profileID, storage: storage)
        self.sleep = sleep
        isConfigured = !authorization.clientID.isEmpty
        filterBook = GitHubFilterBook(defaults: defaults, isPrivate: isPrivate)
        activity = GitHubActivityMemory(defaults: defaults, isPrivate: isPrivate)
        var report: (@MainActor (Error) -> Void)?
        previews = GitHubPreviewLoader(client: client) { report?($0) }
        signIn = GitHubSignIn(authorization: authorization, sleep: sleep)
        report = { [weak self] in self?.handleServiceFailure($0) }
    }

    deinit {
        monitorTask?.cancel()
        loadTask?.cancel()
        pagingTask?.cancel()
        throttleTask?.cancel()
    }

    var filters: [GitHubFilter] {
        filterBook.filters
    }

    var selectedFilterID: String {
        filterBook.selectedID
    }

    var selectedFilter: GitHubFilter {
        filterBook.selected
    }

    var isInbox: Bool {
        filterBook.isInbox
    }

    var pullRequests: [GitHubInboxPR] {
        pages.pullRequests
    }

    var notifications: [GitHubNotification] {
        pages.notifications
    }

    var totalPRs: Int {
        pages.totalPRs
    }

    var nextCursor: String? {
        pages.nextCursor
    }

    var hasMoreNotifications: Bool {
        pages.hasMoreNotifications
    }

    var isConnecting: Bool {
        signIn.isConnecting
    }

    var deviceCode: GitHubDeviceCode? {
        signIn.deviceCode
    }

    var retryAfter: Date? {
        rateLimit.retryAfter
    }

    var details: [String: GitHubPRDetails] {
        previews.details
    }

    var looked: [String: GitHubInboxPR] {
        previews.looked
    }

    var detailErrors: [String: String] {
        previews.detailErrors
    }

    var loadingDetails: Set<String> {
        previews.loadingDetails
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
        get { activity.notifies }
        set { setNotifiesAboutPullRequests(newValue) }
    }

    var isRateLimited: Bool {
        retryAfter != nil
    }

    private var isThrottled: Bool {
        rateLimit.isThrottled
    }

    private func scheduleThrottleEnd() {
        throttleTask?.cancel()
        guard let deadline = retryAfter else { return }
        let sleep = sleep
        throttleTask = Task { [weak self] in
            try? await sleep(.seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, rateLimit.retryAfter == deadline else { return }
            rateLimit.retryAfter = nil
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
            previews.lookedUp(key),
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
            previews.noteLooked(pr)
            return pr
        } catch {
            guard connection == connectionGeneration else { return nil }
            handleServiceFailure(error)
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
            handleServiceFailure(error)
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
        previews.thread(for: item)
    }

    private func loadThread(for notification: GitHubNotification) {
        previews.loadThread(for: notification, token: token, isBlocked: needsReconnect || isThrottled)
    }

    @discardableResult
    private func fetchDetails(for pr: GitHubInboxPR, force: Bool = false) -> Task<GitHubPRDetails?, Never>? {
        previews.fetchDetails(
            for: pr, token: token, includeTeams: hasOrgAccess == true, force: force,
            isBlocked: needsReconnect, isThrottled: isThrottled
        )
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
        activity.setNotifies(value)
    }

    private func announceChanges(authored: [GitHubInboxPR], notifications items: [GitHubNotification], fetchedAt: Date) {
        for update in activity.changes(authored: authored, notifications: items, fetchedAt: fetchedAt, login: account?.login) {
            announce?(update)
        }
    }

    private func forgetSnapshots() {
        activity.forget()
    }

    func selectFilter(_ id: String) {
        guard filterBook.select(id) else { return }
        filterChanged()
    }

    func saveFilter(_ filter: GitHubFilter) {
        guard filterBook.save(filter) else { return }
        filterChanged()
    }

    func deleteFilter(_ id: String) {
        let result = filterBook.delete(id)
        guard result.deleted, result.wasSelected else { return }
        filterChanged()
    }

    private func filterChanged() {
        clearSelection()
        resetFilterResults()
        refreshFilter()
    }

    private func resetFilterResults() {
        pagingTask?.cancel()
        isLoadingMore = false
        pages.resetPullRequests()
        filterFetchedAt = nil
    }

    private func refreshFilter() {
        if !isInbox {
            refresh(.filter)
        } else if !isFresh(triageFetchedAt) {
            refresh(.full)
        }
    }

    func connect(includePrivate: Bool, open: @escaping @MainActor (URL) -> Void) {
        guard !isPrivate, !signIn.isConnecting else { return }
        errorMessage = nil
        signIn.begin(
            includePrivate: includePrivate,
            open: open,
            authorized: { [weak self] credential in
                guard let self else { return {} }
                let user = try await client.account(token: credential)
                return { [weak self] in
                    guard let self else { return }
                    try store.save(credential)
                    resetData()
                    forgetSnapshots()
                    token = credential
                    account = user
                    started = true
                    hasConnection = true
                    needsReconnect = false
                    beginMonitoring()
                }
            },
            failed: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
    }

    func cancelSignIn() {
        signIn.cancel()
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
        pages.reset()
        triage = GitHubTriage()
        previews.reset()
        triageFetchedAt = nil
        filterFetchedAt = nil
        clearSelection()
        markingRead = []
        hasPrivateAccess = nil
        hasOrgAccess = nil
        requiresSSO = false
        lastUpdated = nil
        rateLimit.reset()
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

    private func refresh(_ requested: GitHubRefreshScope) {
        guard !isPrivate, let token, !needsReconnect, !isThrottled,
              let scope = GitHubRefreshScope.merged(requested, into: runningScope) else { return }
        generation += 1
        let request = generation
        let pageGeneration = pages.generation
        loadTask?.cancel()
        isRefreshing = true
        runningScope = scope
        let fetch = GitHubInboxFetch(
            filter: scope == .background || isInbox ? nil : selectedFilter,
            notificationsModified: pages.notificationsModified,
            knownNotifications: notifications,
            knownRepositories: triage.authored.map(\.repository.nameWithOwner),
            covered: Set((triage.reviewRequested + triage.authored).map(\.key)),
            wantsNotifications: scope != .filter,
            wantsTriage: scope == .full,
            wantsAuthored: scope == .background && notifiesAboutPullRequests
        )
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
                let results = await fetch.run(login: user.login, client: client, token: token)
                guard request == generation, !Task.isCancelled else { return }
                errorMessage = nil
                if !isThrottled {
                    rateLimit.retryAfter = nil
                }
                apply(results.pullRequests, pages: pageGeneration, fetchedAt: fetchedAt)
                let authored = apply(triage: results.triage, authored: results.authored, fetchedAt: fetchedAt)
                if let selected = selectedPR, let fresh = (pullRequests + triage.all).first(where: { $0.id == selected.id }) {
                    selectedPR = fresh
                    loadDetails(for: fresh)
                }
                apply(results.inbox)
                if let authored, case .success(let page) = results.inbox {
                    announceChanges(authored: authored, notifications: page.isUnchanged ? [] : page.items, fetchedAt: fetchedAt)
                }
                if errorMessage == nil {
                    lastUpdated = .now
                    rateLimit.recovered()
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
        let request = pages.generation
        pagingTask = Task { [weak self] in
            guard let self else { return }
            defer { if request == pages.generation { isLoadingMore = false } }
            do {
                if showNotifications {
                    let page = try await client.notifications(before: pages.oldestNotification?.addingTimeInterval(1), token: token)
                    guard request == pages.generation, !Task.isCancelled else { return }
                    pages.append(page)
                } else {
                    let page = try await client.pullRequests(query: selectedFilter.searchQuery(login: account.login), cursor: nextCursor, token: token)
                    guard request == pages.generation, !Task.isCancelled else { return }
                    pages.append(page)
                }
            } catch {
                if request == pages.generation, !Task.isCancelled {
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
                pages.markRead(notification)
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
            rateLimit.note(limitedUntil: date)
        }
    }

    private func handleServiceFailure(_ error: Error) {
        if case GitHubFailure.unauthorized = error {
            handle(error)
        } else if case GitHubFailure.rateLimited = error {
            handle(error)
        }
    }
}

private extension GitHubPanelModel {
    func apply(_ result: Result<GitHubPRPage, Error>?, pages: Int, fetchedAt: Date) {
        switch result {
        case .success(let page) where pages == self.pages.generation:
            self.pages.applyFirstPage(page)
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
            pages.applyFirstPage(page)
            hasPrivateAccess = page.scopes.map { $0.contains("repo") }
            hasOrgAccess = page.scopes.map { !$0.isDisjoint(with: ["read:org", "write:org", "admin:org"]) }
            requiresSSO = page.requiresSSO
        case .failure(let error):
            handle(error)
        case nil:
            break
        }
    }
}
