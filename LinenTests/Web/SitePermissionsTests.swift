// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

private func temporaryStore() -> SitePermissions {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SitePermissionsTests-\(UUID().uuidString).json")
    return SitePermissions(storageURL: url)
}

/// The ledger's rules: ask is the unrecorded default, deny and allow are
/// records, and setting ask again is how a record is forgotten.
struct SitePermissionsStoreTests {
    @Test func anUnknownSiteGetsAsked() {
        let store = temporaryStore()
        #expect(store.policy(for: "https://example.com", .camera) == .ask)
        #expect(store.assistantAccess(for: "https://example.com") == .ask)
    }

    @Test func answersAreKeptPerSitePerPermission() {
        let store = temporaryStore()
        store.set(.allow, for: "https://meet.example.com", .microphone)
        store.set(.deny, for: "https://meet.example.com", .camera)
        #expect(store.policy(for: "https://meet.example.com", .microphone) == .allow)
        #expect(store.policy(for: "https://meet.example.com", .camera) == .deny)
        #expect(store.policy(for: "https://meet.example.com", .location) == .ask)
        #expect(store.policy(for: "https://other.example.com", .microphone) == .ask)
    }

    @Test func settingAskForgetsTheRecord() {
        let store = temporaryStore()
        store.set(.deny, for: "https://example.com", .location)
        store.set(.ask, for: "https://example.com", .location)
        #expect(store.policy(for: "https://example.com", .location) == .ask)
        #expect(store.origins(for: .location).isEmpty)
    }

    @Test func assistantAccessIsKeptPerOrigin() {
        let store = temporaryStore()
        store.setAssistantAccess(.readOnly, for: "https://example.com")
        store.setAssistantAccess(.control, for: "https://example.com:8443")

        #expect(store.assistantAccess(for: "https://example.com") == .readOnly)
        #expect(store.assistantAccess(for: "http://example.com") == .ask)
        #expect(store.assistantAccess(for: "https://example.com:8443") == .control)
        #expect(store.assistantOrigins == ["https://example.com", "https://example.com:8443"])
    }

    @Test func askingAgainForgetsAssistantAccess() {
        let store = temporaryStore()
        store.setAssistantAccess(.deny, for: "https://example.com")
        store.setAssistantAccess(.ask, for: "https://example.com")

        #expect(store.assistantAccess(for: "https://example.com") == .ask)
        #expect(store.assistantOrigins.isEmpty)
    }

    @Test func alwaysActiveIsKeptPerOrigin() {
        let store = temporaryStore()
        store.setKeepsActive(true, for: "https://example.com")
        store.setKeepsActive(true, for: "https://example.com:8443")

        #expect(store.keepsActive("https://example.com"))
        #expect(!store.keepsActive("http://example.com"))
        #expect(store.keptActiveOrigins == ["https://example.com", "https://example.com:8443"])

        store.setKeepsActive(false, for: "https://example.com")
        #expect(!store.keepsActive("https://example.com"))
        #expect(store.keptActiveOrigins == ["https://example.com:8443"])
    }

    @Test func automaticPictureIsAllowedUntilAWebsiteOptsOut() {
        let store = temporaryStore()
        #expect(store.allowsAutomaticPicture("https://example.com"))

        store.setAllowsAutomaticPicture(false, for: "https://example.com")
        #expect(!store.allowsAutomaticPicture("https://example.com"))
        #expect(store.allowsAutomaticPicture("http://example.com"))
        #expect(store.noAutomaticPictureOrigins == ["https://example.com"])

        store.setAllowsAutomaticPicture(true, for: "https://example.com")
        #expect(store.allowsAutomaticPicture("https://example.com"))
        #expect(store.noAutomaticPictureOrigins.isEmpty)
    }

    @Test func hostsCompareCaseInsensitivelyAndIgnoreTheRootDot() {
        let store = temporaryStore()
        store.set(.allow, for: "HTTPS://Example.COM.", .notifications)
        #expect(store.policy(for: "https://example.com", .notifications) == .allow)
    }

    /// The point of keying on the origin: a grant given to the real site is
    /// not one the plaintext version of it can spend, or another port.
    @Test func aGrantDoesNotCrossSchemeOrPort() {
        let store = temporaryStore()
        store.set(.allow, for: "https://example.com", .location)
        #expect(store.policy(for: "http://example.com", .location) == .ask)
        #expect(store.policy(for: "https://example.com:8443", .location) == .ask)
        // The scheme's own default port is the same site written longhand.
        #expect(store.policy(for: "https://example.com:443", .location) == .allow)
    }

    /// Bare-host records still answer rather than becoming a site the user
    /// has to allow again. The fixture is written by the store and then
    /// re-keyed, so it is in whatever shape `Snapshot` encodes.
    @Test func bareHostRecordsMigrateToHTTPS() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsMigration-\(UUID().uuidString).json")

        let writer = SitePermissions(storageURL: url)
        writer.set(.allow, for: "example.com", .camera)
        await writer.waitForPendingSave()
        let written = try String(contentsOf: url, encoding: .utf8)
        try written
            .replacingOccurrences(of: "https:\\/\\/example.com", with: "example.com")
            .replacingOccurrences(of: "https://example.com", with: "example.com")
            .write(to: url, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("\"example.com\""))

        let store = SitePermissions(storageURL: url)
        #expect(store.policy(for: "https://example.com", .camera) == .allow)
        #expect(store.origins(for: .camera) == ["https://example.com"])
    }

    @Test func filesFromBeforeAssistantAccessStillLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsLegacy-\(UUID().uuidString).json")
        let json = """
            {"defaults":[],"records":{"https://example.com":["camera","allow"]}}
            """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = SitePermissions(storageURL: url)
        #expect(store.policy(for: "https://example.com", .camera) == .allow)
        #expect(store.assistantOrigins.isEmpty)
    }

    @Test func assistantAccessSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsAssistant-\(UUID().uuidString).json")
        let writer = SitePermissions(storageURL: url)
        writer.setAssistantAccess(.control, for: "https://example.com")
        await writer.waitForPendingSave()

        let reader = SitePermissions(storageURL: url)
        #expect(reader.assistantAccess(for: "https://example.com") == .control)
    }

    @Test func alwaysActiveSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsAlwaysActive-\(UUID().uuidString).json")
        let writer = SitePermissions(storageURL: url)
        writer.setKeepsActive(true, for: "HTTPS://Example.COM.")
        await writer.waitForPendingSave()

        let reader = SitePermissions(storageURL: url)
        #expect(reader.keepsActive("https://example.com"))
        #expect(reader.keptActiveOrigins == ["https://example.com"])
    }

    @Test func noAutomaticPictureSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsAutomaticPicture-\(UUID().uuidString).json")
        let writer = SitePermissions(storageURL: url)
        writer.setAllowsAutomaticPicture(false, for: "HTTPS://Example.COM.")
        await writer.waitForPendingSave()

        let reader = SitePermissions(storageURL: url)
        #expect(!reader.allowsAutomaticPicture("https://example.com"))
        #expect(reader.noAutomaticPictureOrigins == ["https://example.com"])
    }

    @Test func anAutoplayAnswerIsKeptPerOrigin() {
        let store = temporaryStore()
        store.setAutoplay(.block, for: "HTTPS://Example.COM.")
        store.setAutoplay(.silent, for: "https://video.example.com")

        #expect(store.autoplay(for: "https://example.com") == .block)
        #expect(store.autoplay(for: "https://video.example.com") == .silent)
        #expect(store.autoplay(for: "http://example.com") == nil)
        #expect(store.autoplay(for: "https://nobody.example.com") == nil)
        #expect(store.autoplayOrigins == ["https://example.com", "https://video.example.com"])
    }

    @Test func aPopUpAnswerIsKeptPerOrigin() {
        let store = temporaryStore()
        store.setPopups(.allow, for: "https://example.com")
        store.setPopups(.block, for: "https://example.com:8443")

        #expect(store.popups(for: "https://example.com") == .allow)
        #expect(store.popups(for: "https://example.com:8443") == .block)
        #expect(store.popups(for: "https://other.example.com") == nil)
        #expect(store.popupOrigins == ["https://example.com", "https://example.com:8443"])
    }

    @Test func clearingAWebsitesMediaAnswersForgetsThem() {
        let store = temporaryStore()
        store.setAutoplay(.block, for: "https://example.com")
        store.setPopups(.block, for: "https://example.com")

        store.setAutoplay(nil, for: "https://example.com")
        store.setPopups(nil, for: "https://example.com")

        #expect(store.autoplay(for: "https://example.com") == nil)
        #expect(store.popups(for: "https://example.com") == nil)
        #expect(store.autoplayOrigins.isEmpty)
        #expect(store.popupOrigins.isEmpty)
    }

    @Test func aPageThatIsNoWebsiteRecordsNothing() {
        let store = temporaryStore()
        store.setAutoplay(.block, for: "")
        store.setPopups(.block, for: "")

        #expect(store.autoplayOrigins.isEmpty)
        #expect(store.popupOrigins.isEmpty)
    }

    @Test func mediaAnswersSurviveRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitePermissionsMedia-\(UUID().uuidString).json")
        let writer = SitePermissions(storageURL: url)
        writer.setAutoplay(.silent, for: "HTTPS://Example.COM.")
        writer.setPopups(.allow, for: "https://example.com")
        await writer.waitForPendingSave()

        let reader = SitePermissions(storageURL: url)
        #expect(reader.autoplay(for: "https://example.com") == .silent)
        #expect(reader.popups(for: "https://example.com") == .allow)
        #expect(reader.autoplayOrigins == ["https://example.com"])
        #expect(reader.popupOrigins == ["https://example.com"])
    }

    @Test func onlyATrustworthyOriginCanHoldAPermission() {
        #expect(SitePermissions.isPotentiallyTrustworthy(URL(string: "https://example.com")))
        #expect(SitePermissions.isPotentiallyTrustworthy(URL(string: "http://localhost:3000")))
        #expect(SitePermissions.isPotentiallyTrustworthy(URL(string: "http://127.0.0.53")))
        #expect(!SitePermissions.isPotentiallyTrustworthy(URL(string: "http://example.com")))
        #expect(!SitePermissions.isPotentiallyTrustworthy(URL(string: "http://notlocalhost.com")))
    }

    /// A literal address is one site written in brackets, and a socket scheme
    /// carries the same default ports as the page scheme it belongs to.
    @Test func anAddressIsReducedToTheSiteItBelongsTo() {
        #expect(SitePermissions.origin(for: URL(string: "https://Example.COM./a/b?q=1")) == "https://example.com")
        #expect(SitePermissions.origin(for: URL(string: "https://example.com:8443/")) == "https://example.com:8443")
        #expect(SitePermissions.origin(for: URL(string: "https://[::1]:443/x")) == "https://[::1]")
        #expect(SitePermissions.origin(for: URL(string: "http://[2001:db8::1]:8080/")) == "http://[2001:db8::1]:8080")
        #expect(SitePermissions.origin(for: URL(string: "wss://chat.example.com:443/")) == "wss://chat.example.com")
        #expect(SitePermissions.origin(for: URL(string: "ws://chat.example.com:80/")) == "ws://chat.example.com")
        #expect(SitePermissions.origin(for: URL(string: "ws://chat.example.com:8080/")) == "ws://chat.example.com:8080")
    }

    @Test func anAddressWithNoSiteInItHasNoOrigin() {
        #expect(SitePermissions.origin(for: nil).isEmpty)
        #expect(SitePermissions.origin(for: URL(string: "file:///tmp/page.html")).isEmpty)
        #expect(SitePermissions.origin(for: URL(string: "about:blank")).isEmpty)
    }

    /// The address bar's spelling for an ordinary site, the whole origin
    /// whenever dropping a part would make two sites look like one.
    @Test func theDisplayNameHidesOnlyTheRedundantParts() {
        #expect(SitePermissions.displayName(for: "https://example.com") == "example.com")
        #expect(SitePermissions.displayName(for: "http://localhost:3000") == "http://localhost:3000")
        #expect(SitePermissions.displayName(for: "https://example.com:8443") == "https://example.com:8443")
    }

    @Test func theDefaultAppliesOnlyToUnlistedSites() {
        let store = temporaryStore()
        store.setDefault(.deny, for: .location)
        store.set(.allow, for: "https://maps.example.com", .location)
        #expect(store.policy(for: "https://anywhere.example.com", .location) == .deny)
        #expect(store.policy(for: "https://maps.example.com", .location) == .allow)
    }

    @Test func removeAllClearsOnePermissionAndLeavesTheRest() {
        let store = temporaryStore()
        store.set(.allow, for: "https://a.example.com", .microphone)
        store.set(.deny, for: "https://b.example.com", .microphone)
        store.set(.deny, for: "https://b.example.com", .camera)
        store.removeAll(for: .microphone)
        #expect(store.origins(for: .microphone).isEmpty)
        #expect(store.policy(for: "https://b.example.com", .camera) == .deny)
    }

    @Test func clearingEverythingAlsoClearsAssistantAccess() {
        let store = temporaryStore()
        store.set(.allow, for: "https://example.com", .camera)
        store.setAssistantAccess(.control, for: "https://example.com")
        store.setKeepsActive(true, for: "https://example.com")
        store.setAllowsAutomaticPicture(false, for: "https://example.com")
        store.setAutoplay(.block, for: "https://example.com")
        store.setPopups(.allow, for: "https://example.com")

        store.removeEverything()

        #expect(store.records.isEmpty)
        #expect(store.assistantOrigins.isEmpty)
        #expect(store.keptActiveOrigins.isEmpty)
        #expect(store.noAutomaticPictureOrigins.isEmpty)
        #expect(store.autoplayOrigins.isEmpty)
        #expect(store.popupOrigins.isEmpty)
    }
}

/// The ask's lifecycle: how the three verbs and the non-answer resolve, and
/// what leaving the site takes with it.
struct TabPermissionCenterTests {
    /// Runs `decide` while this turn answers the ask it raises.
    private func decide(
        _ permission: WebPermission,
        on center: TabPermissionCenter,
        answering answer: TabPermissionCenter.AskAnswer
    ) async -> Bool {
        async let decision = center.decide(permission)
        for _ in 0..<1000 where center.currentAsk == nil {
            await Task.yield()
        }
        #expect(center.currentAsk?.permission == permission)
        #expect(center.isPopoverPresented)
        center.answer(answer)
        return await decision
    }

    @Test func onlyOnceLastsExactlyUntilTheSiteChanges() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(await decide(.microphone, on: center, answering: .once))
        // Granted for the visit: no second ask.
        #expect(await center.decide(.microphone))
        #expect(center.pendingAsks.isEmpty)
        // A new site starts clean.
        center.pageChanged(url: URL(string: "https://elsewhere.com/")!)
        #expect(center.sessionGrants.isEmpty)
        #expect(center.rows.isEmpty)
    }

    /// A store locator that asks the moment the page loads, and again when its
    /// map mounts, raised two identical popovers - so the first click looked
    /// like nothing had happened.
    @Test func repeatedAsksForOnePermissionAreOneQuestion() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        async let first = center.decide(.location)
        async let second = center.decide(.location)
        async let third = center.decide(.location)
        for _ in 0..<1000 where (center.pendingAsks.first?.waitingCount ?? 0) < 3 {
            await Task.yield()
        }
        #expect(center.pendingAsks.count == 1)
        #expect(center.pendingAsks.first?.waitingCount == 3)

        center.answer(.once)
        #expect(await first)
        #expect(await second)
        #expect(await third)
        // One click answered all three, so the panel has nothing left to ask.
        #expect(center.pendingAsks.isEmpty)
        #expect(!center.isPopoverPresented)
    }

    /// Two permissions are two questions; answering the first leaves the panel
    /// up for the second.
    @Test func answeringOneOfTwoQuestionsKeepsThePanelUp() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        async let camera = center.decide(.camera)
        for _ in 0..<1000 where center.currentAsk == nil {
            await Task.yield()
        }
        async let microphone = center.decide(.microphone)
        for _ in 0..<1000 where center.pendingAsks.count < 2 {
            await Task.yield()
        }

        center.answer(.once)
        #expect(center.isPopoverPresented)
        #expect(center.currentAsk?.permission == .microphone)
        center.answer(.deny)
        #expect(await camera)
        #expect(await microphone == false)
        #expect(!center.isPopoverPresented)
    }

    @Test func alwaysAllowAndDenyOutliveTheVisit() async {
        let store = temporaryStore()
        let center = TabPermissionCenter(store: store)
        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(await decide(.camera, on: center, answering: .always))
        #expect(await decide(.location, on: center, answering: .deny) == false)
        #expect(store.policy(for: "https://example.com", .camera) == .allow)
        #expect(store.policy(for: "https://example.com", .location) == .deny)
        // Denied is remembered: no ask, straight refusal.
        #expect(await center.decide(.location) == false)
    }

    @Test func aDismissedAskRecordsNothing() async {
        let store = temporaryStore()
        let center = TabPermissionCenter(store: store)
        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(await decide(.notifications, on: center, answering: .dismissed) == false)
        // Nothing stored, so the site may ask again.
        #expect(store.policy(for: "https://example.com", .notifications) == .ask)
    }

    @Test func leavingThePageResolvesItsAskUnanswered() async {
        let store = temporaryStore()
        let center = TabPermissionCenter(store: store)
        center.pageChanged(url: URL(string: "https://example.com/")!)
        async let decision = center.decide(.camera)
        for _ in 0..<1000 where center.currentAsk == nil {
            await Task.yield()
        }
        center.pageChanged(url: URL(string: "https://elsewhere.com/")!)
        #expect(await decision == false)
        #expect(store.policy(for: "https://example.com", .camera) == .ask)
        #expect(!center.isPopoverPresented)
    }

    @Test func theBadgeWearsTheMostUrgentState() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(center.badge == .hidden)

        #expect(await decide(.microphone, on: center, answering: .once))
        #expect(center.badge == .granted(.microphone))

        _ = await decide(.location, on: center, answering: .deny)
        #expect(center.badge == .denied(.location))

        center.setLive(.microphone, true)
        #expect(center.badge == .live(.microphone))
        center.setLive(.microphone, false)
        #expect(center.badge == .denied(.location))
    }

    /// Refused without being asked about, and without being written down -
    /// the site may try again once it is reachable over TLS.
    @Test func aPlaintextPageIsRefusedWithoutAsking() async {
        let store = temporaryStore()
        let center = TabPermissionCenter(store: store)
        center.pageChanged(url: URL(string: "http://example.com/")!)

        #expect(await center.decide(.location) == false)
        #expect(center.pendingAsks.isEmpty)
        #expect(!center.isPopoverPresented)
        #expect(store.policy(for: "http://example.com", .location) == .ask)
        #expect(center.badge == .denied(.location))
    }

    /// The gate sits above the store, so a migrated bare-host record cannot
    /// be spent by the http version of that host.
    @Test func aStoredGrantDoesNotSurviveOnAPlaintextPage() async {
        let store = temporaryStore()
        store.set(.allow, for: "https://example.com", .camera)
        let center = TabPermissionCenter(store: store)

        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(await center.decide(.camera))

        center.pageChanged(url: URL(string: "http://example.com/")!)
        #expect(!center.isGranted(.camera))
        #expect(await center.decide(.camera) == false)
    }

    /// Same host, different scheme, is a different site: the visit's grants
    /// do not follow the tab across.
    @Test func changingSchemeStartsTheSiteOver() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        #expect(await decide(.microphone, on: center, answering: .once))

        center.pageChanged(url: URL(string: "http://example.com/")!)
        #expect(center.sessionGrants.isEmpty)
        #expect(center.origin == "http://example.com")
    }

    /// "Clear website data" reaches the open tab, not only the ledger.
    @Test func clearingSiteDataCutsWhatIsLiveOnAnOpenTab() async {
        let store = temporaryStore()
        let center = TabPermissionCenter(store: store)
        center.pageChanged(url: URL(string: "https://example.com/")!)
        var revoked: [WebPermission] = []
        center.onRevoke = { revoked.append($0) }

        #expect(await decide(.camera, on: center, answering: .once))
        center.setLive(.camera, true)

        center.siteDataCleared()
        #expect(revoked == [.camera])
        #expect(center.sessionGrants.isEmpty)
        #expect(center.rows.isEmpty)
    }

    @Test func revokingSomethingLiveCutsTheStream() async {
        let center = TabPermissionCenter(store: temporaryStore())
        center.pageChanged(url: URL(string: "https://example.com/")!)
        var revoked: [WebPermission] = []
        center.onRevoke = { revoked.append($0) }

        #expect(await decide(.microphone, on: center, answering: .always))
        center.setLive(.microphone, true)
        center.set(.deny, for: .microphone)
        #expect(revoked == [.microphone])
        #expect(!center.live.contains(.microphone))
        // And the refusal is now the stored answer.
        #expect(await center.decide(.microphone) == false)
    }
}
