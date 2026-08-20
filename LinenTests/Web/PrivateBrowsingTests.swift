// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Testing
import WebKit

@testable import Linen

/// The promise a private tab makes: nothing it does outlives it. Each claim
/// is tested at the seam where it would leak - the session table, the
/// reopen list, the permission store.
@MainActor
@Suite(.boundedWebViews)
struct PrivateBrowsingTests {
    private func makeModel(database: AppDatabase = .temporary()) -> BrowserModel {
        BrowserModel(database: database, sitePermissions: makePermissions())
    }

    private func makePermissions() -> SitePermissions {
        SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PrivateBrowsingPermissions-\(UUID().uuidString).json")
        )
    }

    /// A model in private browsing. There is no per-tab private any more, so
    /// this is the only way a private tab exists.
    private func makePrivateModel(database: AppDatabase = .temporary()) -> BrowserModel {
        let permissions = makePermissions()
        let model = BrowserModel(database: database, sitePermissions: permissions)
        model.adopt(database: database, sitePermissions: permissions, privately: true)
        return model
    }

    /// The store comes from the profile now, not from the tab. There is no
    /// per-tab private path left to check - a tab is private because the
    /// profile it was opened in is.
    @Test func thePrivateProfileBrowsesInAnEphemeralStore() {
        #expect(!Profile.privateBrowsing().makeDataStore().isPersistent)
        // And an ordinary profile does not, or every profile is "private".
        #expect(Profile.original().makeDataStore().isPersistent)
    }

    /// Two entries are two sessions. The store is made fresh each time the
    /// profile is opened, so nothing signed into last time is still signed in.
    @Test func eachEntryIntoPrivateBrowsingIsANewSession() {
        let priv = Profile.privateBrowsing()
        #expect(priv.makeDataStore() !== priv.makeDataStore())
    }

    // MARK: - Private browsing as a profile

    /// The profile is the answer, not the call site: inside private browsing
    /// an ordinary ⌘T is a private tab, so nothing has to remember to ask.
    @Test func everyTabIsPrivateInsideAPrivateProfile() {
        let model = makeModel()
        model.adopt(
            database: .temporary(),
            sitePermissions: makePermissions(),
            privately: true
        )

        #expect(model.newTab().isPrivate)
        #expect(model.newTab(url: URL(string: "https://example.com")).isPrivate)
    }

    /// And leaving puts it back, or every tab after a private session would
    /// quietly go unrecorded.
    @Test func tabsStopBeingPrivateOnTheWayOut() {
        let model = makeModel()
        model.adopt(
            database: .temporary(),
            sitePermissions: makePermissions(),
            privately: true
        )
        #expect(model.newTab().isPrivate)

        model.adopt(
            database: .temporary(),
            sitePermissions: makePermissions(),
            privately: false
        )
        #expect(!model.newTab().isPrivate)
    }

    /// The reason this became a profile. The agent's log had no privacy check
    /// of its own - a private tab's prompts, steps and token counts went to
    /// disk like any other. A database in memory closes that without every
    /// store having to remember to ask.
    @Test func theAgentsLogWritesNowhereInPrivateBrowsing() throws {
        let database = AppDatabase.temporary()
        let log = ConversationLog(database: database)

        let task = log.beginTask("something private", tabID: UUID())
        log.completeTask(task, response: "an answer")

        // It works normally inside the session...
        #expect(!log.traces.isEmpty)
        // ...and there is no file it could have reached.
        #expect(Profile.privateBrowsing().databaseURL == nil)
    }

    /// Every tab in the session shares one store, so signing in and following
    /// a link from that page stays signed in. It falls out of the store
    /// belonging to the profile rather than to each tab.
    @Test func everyTabInAPrivateSessionSharesItsStore() {
        let model = makePrivateModel()
        let first = model.newTab()
        let second = model.newTab()

        #expect(first.webView.configuration.websiteDataStore
            === second.webView.configuration.websiteDataStore)
    }

    /// Closing tabs is not leaving. Ending the session when the last tab shut
    /// meant closing everything while still inside private browsing signed you
    /// out of what you were doing.
    @Test func closingEveryTabDoesNotEndTheSession() {
        let model = makePrivateModel()
        let first = model.newTab()
        let store = first.webView.configuration.websiteDataStore
        model.close(first)

        let later = model.newTab()
        #expect(later.webView.configuration.websiteDataStore === store)
        #expect(later.isPrivate)
    }

    /// A private session does keep its tabs - in a database held in memory,
    /// which is what lets switching to another profile and back be a return
    /// rather than a fresh start. The file is what it must never reach, and
    /// there is no file.
    @Test func aPrivateSessionKeepsItsTabsInMemory() throws {
        let database = AppDatabase.temporary()
        let model = makePrivateModel(database: database)
        _ = model.newTab(url: URL(string: "https://example.com/a"))
        _ = model.newTab(url: URL(string: "https://example.com/b"))
        model.saveBlocking()

        let saved = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionTab")
        }
        #expect(saved == 2)
        // And the profile it was written for has nowhere on disk to be.
        #expect(Profile.privateBrowsing().databaseURL == nil)
    }

    /// Switching away writes the session down so switching back can read it.
    /// A pending debounced save must not survive the swap: it would land two
    /// seconds later on whichever database the model had moved on to.
    @Test func closingEveryTabLeavesNoSaveQueuedAgainstTheOldDatabase() throws {
        let leaving = AppDatabase.temporary()
        let arriving = AppDatabase.temporary()
        let model = makeModel(database: leaving)
        _ = model.newTab(url: URL(string: "https://example.com/a"))

        model.closeAllTabs()
        model.adopt(database: arriving, sitePermissions: makePermissions())
        _ = model.newTab(url: URL(string: "https://example.com/b"))
        model.saveBlocking()

        // The arriving profile has its own tab and nothing the old one queued.
        let saved = try arriving.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionTab")
        }
        #expect(saved == 1)
        // And what was open before is still readable where it was written.
        let kept = try leaving.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionTab")
        }
        #expect(kept == 1)
    }

    /// The invariant behind that: a private tab must never be written into a
    /// database that has a file. Only the profile's own ephemeral one.
    @Test func aPrivateTabIsRefusedByAProfileThatWritesToDisk() throws {
        let database = AppDatabase.temporary()
        let model = makeModel(database: database)
        // A tab that is private while the model is not - which the profile
        // model makes unreachable, and which must still be refused.
        model.adopt(
            database: database,
            sitePermissions: makePermissions(),
            privately: true
        )
        _ = model.newTab(url: URL(string: "https://example.com/a"))
        model.adopt(
            database: database,
            sitePermissions: makePermissions(),
            privately: false
        )
        model.saveBlocking()

        let saved = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionTab")
        }
        #expect(saved == 0)
    }

    /// ⇧⌘T must not resurrect something the session was meant to forget.
    @Test func closingAPrivateTabLeavesNothingToReopen() {
        let model = makePrivateModel()
        let tab = model.newTab()

        model.close(tab)
        #expect(!model.canReopenClosedTab)
    }

    /// And an ordinary profile still writes its tabs down, or the guard above
    /// would pass by doing nothing at all.
    @Test func anOrdinaryProfileStillSavesItsTabs() throws {
        let database = AppDatabase.temporary()
        let model = makeModel(database: database)
        _ = model.newTab()
        model.saveBlocking()

        let saved = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionTab")
        }
        #expect(saved == 1)
    }

    // MARK: - The restore boundary

    /// The bug this suite exists for: entering private browsing must never
    /// bring back the tabs of the profile being left. The flow below is the
    /// coordinator's own - save and close, adopt the session's stores, then
    /// restore - against a fresh session, which has nothing to restore.
    @Test func aFreshPrivateSessionRestoresNothing() throws {
        let personal = AppDatabase.temporary()
        let permissions = makePermissions()
        let model = BrowserModel(database: personal, sitePermissions: permissions)
        for path in ["a", "b", "c"] {
            _ = model.newTab(url: URL(string: "https://personal.example/\(path)"))
        }
        model.saveBlocking()

        model.closeAllTabs()
        let session = PrivateBrowsingSession()
        model.adopt(database: session.database, sitePermissions: permissions, privately: true)
        model.restoreSession(force: true)

        #expect(model.tabs.isEmpty)
    }

    /// The invariant that makes the promise hold whatever a caller does: a
    /// private model handed a database with a file refuses it. Nothing can be
    /// restored out of the file, and nothing private can be written into it.
    @Test func aPrivateModelRefusesADatabaseThatHasAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateRefusal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let onDisk = AppDatabase(at: url)
        let permissions = makePermissions()

        let writer = BrowserModel(database: onDisk, sitePermissions: permissions)
        _ = writer.newTab(url: URL(string: "https://personal.example/kept"))
        writer.saveBlocking()

        let model = BrowserModel(database: .temporary(), sitePermissions: permissions)
        model.adopt(database: onDisk, sitePermissions: permissions, privately: true)
        model.restoreSession(force: true)
        #expect(model.tabs.isEmpty)

        _ = model.newTab(url: URL(string: "https://private.example/secret"))
        model.saveBlocking()
        let rows = try onDisk.writer.read { db in
            try String.fetchAll(db, sql: "SELECT url FROM sessionTab")
        }
        #expect(rows == ["https://personal.example/kept"])
    }

    @Test func temporaryDatabasesKnowTheyAreEphemeralAndFilesKnowTheyAreNot() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ephemerality-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(AppDatabase.temporary().isEphemeral)
        #expect(!AppDatabase(at: url).isEphemeral)
    }

    /// The session object is the container; it must be impossible to build
    /// one around stores that would outlive it.
    @Test func aPrivateSessionRefusesPersistentStores() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRefusal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let session = PrivateBrowsingSession(
            database: AppDatabase(at: url),
            dataStore: .default()
        )
        #expect(session.database.isEphemeral)
        #expect(!session.dataStore.isPersistent)
    }

    /// And one built the default way keeps exactly what it was given.
    @Test func aPrivateSessionKeepsEphemeralStoresItWasGiven() {
        let database = AppDatabase.temporary()
        let store = WKWebsiteDataStore.nonPersistent()
        let session = PrivateBrowsingSession(database: database, dataStore: store)
        #expect(session.database.writer === database.writer)
        #expect(session.dataStore === store)
    }

    /// Round trip: personal session, a private interlude, and back. What was
    /// open before comes back; what happened in between is nowhere.
    @Test func leavingPrivateBrowsingRestoresThePersonalSessionUntouched() throws {
        let personal = AppDatabase.temporary()
        let permissions = makePermissions()
        let model = BrowserModel(database: personal, sitePermissions: permissions)
        _ = model.newTab(url: URL(string: "https://personal.example/kept"))
        model.saveBlocking()

        model.closeAllTabs()
        let session = PrivateBrowsingSession()
        model.adopt(database: session.database, sitePermissions: permissions, privately: true)
        model.restoreSession(force: true)
        _ = model.newTab(url: URL(string: "https://private.example/secret"))

        model.closeAllTabs()
        model.adopt(database: personal, sitePermissions: permissions, privately: false)
        model.restoreSession(force: true)

        #expect(model.tabs.map(\.urlString) == ["https://personal.example/kept"])
        let rows = try personal.writer.read { db in
            try String.fetchAll(db, sql: "SELECT url FROM sessionTab")
        }
        #expect(rows == ["https://personal.example/kept"])
    }

    /// Returning to a running session is a return: its own tabs come back
    /// from its own ephemeral database, and only those.
    @Test func returningToAKeptPrivateSessionRestoresOnlyItsOwnTabs() {
        let personal = AppDatabase.temporary()
        let permissions = makePermissions()
        let model = BrowserModel(database: personal, sitePermissions: permissions)
        _ = model.newTab(url: URL(string: "https://personal.example/kept"))
        model.saveBlocking()

        model.closeAllTabs()
        let session = PrivateBrowsingSession()
        model.adopt(database: session.database, sitePermissions: permissions, privately: true)
        model.restoreSession(force: true)
        _ = model.newTab(url: URL(string: "https://private.example/secret"))

        model.closeAllTabs()
        model.adopt(database: personal, sitePermissions: permissions, privately: false)
        model.restoreSession(force: true)

        model.closeAllTabs()
        model.adopt(database: session.database, sitePermissions: permissions, privately: true)
        model.restoreSession(force: true)

        #expect(model.tabs.map(\.urlString) == ["https://private.example/secret"])
        #expect(model.tabs.allSatisfy { $0.isPrivate })
    }

    // MARK: - History

    /// The seam where a visit becomes a row. A private tab's finished
    /// navigation must write nothing, in any database.
    @Test func aPrivateNavigationWritesNoHistoryRow() throws {
        let database = AppDatabase.temporary()
        let model = makePrivateModel(database: database)
        let tab = model.newTab()
        tab.urlString = "https://private.example/page"
        tab.title = "Secret"

        tab.onNavigationFinished?(false)

        let visits = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM historyPage")
        }
        #expect(visits == 0)
    }

    /// The same seam records normally outside private browsing, or the guard
    /// above would pass by recording nothing for anyone.
    @Test func anOrdinaryNavigationStillWritesItsHistoryRow() throws {
        let database = AppDatabase.temporary()
        let model = makeModel(database: database)
        let tab = model.newTab()
        tab.urlString = "https://ordinary.example/page"
        tab.title = "Ordinary"

        tab.onNavigationFinished?(false)

        let visits = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM historyPage")
        }
        #expect(visits == 1)
    }

    // MARK: - Children of a private tab

    /// `window.open`, ⌘-click, "Open Link in New Tab": WebKit builds the new
    /// view from the opener's configuration and the model adopts it. The
    /// child must be private and must share the opener's store.
    @Test func aTabAdoptedFromAPrivateOpenerIsPrivateAndSharesItsStore() {
        let model = makePrivateModel()
        let opener = model.newTab()
        let openerStore = opener.webView.configuration.websiteDataStore

        let adopted = TabWebView(
            frame: .zero,
            configuration: opener.webView.configuration
        )
        let child = model.newTab(activate: true, adopting: adopted)

        #expect(child.isPrivate)
        #expect(child.webView.configuration.websiteDataStore === openerStore)
    }

    // MARK: - Ending the session

    /// The private profile's directory should never exist; if anything ever
    /// put a file there, ending the session removes the lot.
    @Test func endingThePrivateSessionRemovesItsDirectory() async throws {
        let directory = Profile.privateBrowsing().supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("stray.json").path,
            contents: Data("x".utf8)
        )

        await Profile.erase(.privateBrowsing())
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func privateAnswersStayOutOfTheStore() {
        let store = SitePermissions(
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("linen-perms-\(UUID().uuidString).json")
        )
        let center = TabPermissionCenter(store: store)
        center.persistsAnswers = false
        center.pageChanged(url: URL(string: "https://example.com/")!)

        center.set(.allow, for: .camera)
        // Works for the visit, written nowhere.
        #expect(center.isGranted(.camera))
        #expect(store.policy(for: "https://example.com", .camera) == .ask)

        center.set(.deny, for: .camera)
        #expect(!center.isGranted(.camera))
        #expect(store.policy(for: "https://example.com", .camera) == .ask)

        // Leaving the site forgets everything, same as session grants.
        center.pageChanged(url: URL(string: "https://other.example/")!)
        #expect(center.rows.isEmpty)
    }
}

/// Per-site zoom: a level is a decision, the default is the absence of one.
@MainActor
struct PageZoomStoreTests {
    private func makeStore() -> PageZoomStore {
        PageZoomStore(
            file: FileManager.default.temporaryDirectory
                .appendingPathComponent("linen-zoom-\(UUID().uuidString).json")
        )
    }

    @Test func aZoomedSiteIsRemembered() {
        let store = makeStore()
        store.set(1.25, for: "news.example", defaultZoom: 1)
        #expect(store.level(for: "news.example") == 1.25)
        #expect(store.level(for: "other.example") == nil)
    }

    @Test func returningToTheDefaultForgetsTheSite() {
        let store = makeStore()
        store.set(1.25, for: "news.example", defaultZoom: 1)
        store.set(1, for: "news.example", defaultZoom: 1)
        #expect(store.level(for: "news.example") == nil)
    }
}

/// The pool pre-warms views against one data store at a time. A view built
/// for a persistent profile must never be handed to a private tab, nor the
/// other way round.
@MainActor
struct WebViewPoolPrivacyTests {
    @Test func swappingTheStoreRetiresEveryWarmedView() {
        let pool = WebViewPool()
        pool.warmUp()

        let ephemeral = WKWebsiteDataStore.nonPersistent()
        pool.useDataStore(ephemeral)

        let view = pool.acquire()
        #expect(view.configuration.websiteDataStore === ephemeral)
        #expect(!view.configuration.websiteDataStore.isPersistent)
    }

    @Test func swappingBackHandsOutPersistentViewsAgain() {
        let pool = WebViewPool()
        let ephemeral = WKWebsiteDataStore.nonPersistent()
        pool.useDataStore(ephemeral)
        pool.warmUp()

        pool.useDataStore(.default())
        let view = pool.acquire()
        #expect(view.configuration.websiteDataStore === WKWebsiteDataStore.default())
        #expect(view.configuration.websiteDataStore.isPersistent)
    }

    @Test func everyViewAcquiredWhilePrivateSharesTheOneEphemeralStore() {
        let pool = WebViewPool()
        let ephemeral = WKWebsiteDataStore.nonPersistent()
        pool.useDataStore(ephemeral)

        let first = pool.acquire()
        let second = pool.acquire()
        #expect(first.configuration.websiteDataStore === second.configuration.websiteDataStore)
        #expect(first.configuration.websiteDataStore === ephemeral)
    }
}

/// Favicons are the one cache a private page could reach through ordinary
/// UI - the omnibox, a pinned row, the identity popover all fetch by host.
@MainActor
struct PrivateFaviconTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-private-favicons-\(UUID().uuidString)", isDirectory: true)
    }

    private func iconData() throws -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        return try #require(image.tiffRepresentation)
    }

    @Test func aPrivateFaviconNeverTouchesTheDisk() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = FaviconLoader(cacheDirectory: directory)
        loader.persistsToDisk = false

        #expect(loader.store(try iconData(), forHost: "secret.example") != nil)
        // Held for the session...
        #expect(loader.cached(for: "secret.example") != nil)
        // ...and written nowhere.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.isEmpty)
    }

    @Test func endingTheSessionForgetsPrivateFavicons() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = FaviconLoader(cacheDirectory: directory)
        loader.persistsToDisk = false
        loader.store(try iconData(), forHost: "secret.example")

        loader.forgetSessionOnlyIcons()
        #expect(loader.cached(for: "secret.example") == nil)
    }

    @Test func ordinaryFaviconsStillReachTheDisk() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = FaviconLoader(cacheDirectory: directory)

        #expect(loader.store(try iconData(), forHost: "ordinary.example") != nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.count == 1)
    }

    /// Icons cached to disk before the session are still readable in it, the
    /// way private windows read ordinary bookmarks. Read access is fine; the
    /// session must only never write.
    @Test func privateBrowsingStillReadsTheExistingDiskCache() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = FaviconLoader(cacheDirectory: directory)
        loader.store(try iconData(), forHost: "ordinary.example")

        loader.persistsToDisk = false
        #expect(loader.cached(for: "ordinary.example") != nil)
    }
}

/// Profile switches queue. The dropped switch was the restore leak: ⇧⌘N
/// during the close-window switch-back was ignored, and the ordinary
/// session's restored tabs filled the window the user asked to be private.
@MainActor
struct SerialTasksTests {
    @MainActor
    private final class Recorder {
        var order: [Int] = []
    }

    @Test func overlappingRunsBothRunInOrder() async {
        let queue = SerialTasks()
        let recorder = Recorder()

        let first = Task {
            await queue.run {
                recorder.order.append(1)
                try? await Task.sleep(for: .milliseconds(30))
                recorder.order.append(2)
            }
        }
        let second = Task {
            await queue.run {
                recorder.order.append(3)
            }
        }
        await first.value
        await second.value

        #expect(recorder.order == [1, 2, 3])
    }

    @Test func aBurstOfRunsAllRun() async {
        let queue = SerialTasks()
        let recorder = Recorder()

        let tasks = (0..<5).map { index in
            Task {
                await queue.run { recorder.order.append(index) }
            }
        }
        for task in tasks {
            await task.value
        }

        #expect(recorder.order.sorted() == [0, 1, 2, 3, 4])
        #expect(recorder.order.count == 5)
    }
}
