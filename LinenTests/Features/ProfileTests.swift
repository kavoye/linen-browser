// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Profiles, and above all the promise that adding them moves nothing: the
/// profile every installation already has keeps the files the browser has
/// always used, so there is no migration to get wrong.
@MainActor
struct ProfileTests {
    private func makeStore() -> (ProfileStore, URL) {
        let file = URL(filePath: NSTemporaryDirectory())
            .appending(path: "profiles-\(UUID().uuidString).json")
        return (ProfileStore(file: file), file)
    }

    // MARK: - Paths make nothing

    /// Asking where a profile's things would go must not make anywhere for
    /// them. Both getters used to create their folder on the way past, so a
    /// test that only *named* a profile's database left a directory behind in
    /// the real application-support folder - two hundred of them had piled up
    /// there before anyone noticed.
    @Test func namingAProfilesStorageCreatesNothing() throws {
        let profile = Profile(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        let files = FileManager.default

        _ = profile.supportDirectory
        _ = profile.databaseURL
        _ = profile.zoomFile
        _ = profile.permissionsFile
        _ = AppDatabase.url(forProfile: profile.id)

        #expect(!files.fileExists(atPath: profile.supportDirectory.path))
        #expect(!files.fileExists(atPath: try #require(profile.databaseURL).deletingLastPathComponent().path))
    }

    @Test func afirstLaunchHasOneProfileHoldingEverything() {
        let (store, _) = makeStore()

        #expect(store.profiles.count == 1)
        #expect(store.current.isOriginal)
        #expect(!store.hasMultiple)
    }

    /// The whole no-migration claim. If these paths ever move, every existing
    /// installation loses its history, cookies and extensions on upgrade.
    @Test func theOriginalProfileKeepsTheBrowsersOwnFiles() {
        let original = Profile.original()

        #expect(original.databaseURL == AppDatabase.defaultURL)
        #expect(original.supportDirectory == AppDatabase.supportDirectory)
        #expect(original.zoomFile.lastPathComponent == "page-zoom.json")
        #expect(original.permissionsFile.lastPathComponent == "SitePermissions.json")
        // Which is where they already are, not under a Profiles folder.
        #expect(original.databaseURL?.path.contains("/Profiles/") == false)
    }

    @Test func aNewProfileGetsItsOwnDirectory() throws {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")

        #expect(!work.isOriginal)
        #expect(work.databaseURL != Profile.original().databaseURL)
        #expect(try #require(work.databaseURL).path.contains(work.id.uuidString))
        // And its stores sit under it rather than beside everyone else's.
        #expect(work.zoomFile.path.contains(work.id.uuidString))
        #expect(work.permissionsFile.path.contains(work.id.uuidString))
    }

    @Test func twoProfilesNeverShareAStore() {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")
        let school = store.add(name: "School")

        #expect(work.databaseURL != school.databaseURL)
        #expect(work.zoomFile != school.zoomFile)
        #expect(work.permissionsFile != school.permissionsFile)
    }

    @Test func addingAProfileMakesTheSwitcherWorthShowing() {
        let (store, _) = makeStore()
        #expect(!store.hasMultiple)

        store.add(name: "Work")
        #expect(store.hasMultiple)
    }

    @Test func anUnnamedProfileStillGetsAName() {
        let (store, _) = makeStore()
        let profile = store.add(name: "   ")

        #expect(!profile.name.isEmpty)
    }

    @Test func renamingIgnoresBlankNames() throws {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")

        store.rename(work, to: "  ")
        let after = try #require(store.profiles.first { $0.id == work.id })
        #expect(after.name == "Work")

        store.rename(work, to: "Consulting")
        let renamed = try #require(store.profiles.first { $0.id == work.id })
        #expect(renamed.name == "Consulting")
    }

    /// It holds the files that predate profiles, and the browser has to be
    /// somewhere.
    @Test func theOriginalProfileCannotBeDeleted() async {
        let (store, _) = makeStore()
        store.add(name: "Work")

        #expect(store.deletableProfiles.count == 1)
        await store.remove(Profile.original())
        #expect(store.profiles.contains { $0.isOriginal })
    }

    /// Deleting the open profile must not leave the store pointing at a
    /// profile that no longer exists.
    @Test func deletingTheOpenProfileFallsBackToTheOriginal() async {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)
        #expect(store.currentID == work.id)

        await store.remove(work)
        #expect(store.currentID == Profile.originalID)
        #expect(store.current.isOriginal)
    }

    @Test func theChoiceOfProfileSurvivesARelaunch() {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)

        let reopened = ProfileStore(file: file)
        #expect(reopened.profiles.count == 2)
        #expect(reopened.currentID == work.id)
        #expect(reopened.current.name == "Work")
    }

    /// A stored choice naming a profile that has since gone must not leave the
    /// browser pointing at nothing.
    @Test func aMissingCurrentProfileFallsBackRatherThanCrashing() throws {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)

        // The file as it would be after the profile was removed elsewhere.
        let json = """
            {"profiles":[],"currentID":"\(work.id.uuidString)"}
            """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let reopened = ProfileStore(file: file)
        #expect(reopened.currentID == Profile.originalID)
        #expect(reopened.profiles.contains { $0.isOriginal })
    }

    // MARK: - Order and launch

    @Test func theOrderOfProfilesIsTheUsersToArrange() throws {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.add(name: "School")

        store.move(work, to: 0)
        #expect(store.profiles.first?.id == work.id)

        let reopened = ProfileStore(file: file)
        #expect(reopened.profiles.map(\.name) == ["Work", "Personal", "School"])
    }

    @Test func movingPastTheEndsStaysInTheList() {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")

        store.move(work, to: 99)
        #expect(store.profiles.last?.id == work.id)
        store.move(work, to: -5)
        #expect(store.profiles.first?.id == work.id)
    }

    /// A pinned profile beats where the browser happened to be when it quit.
    @Test func aPinnedProfileIsWhatTheNextLaunchOpens() {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.setLaunchProfile(work.id)
        store.markCurrent(Profile.original())

        let reopened = ProfileStore(file: file)
        #expect(reopened.currentID == work.id)
        #expect(reopened.launchProfileID == work.id)
    }

    @Test func noPinnedProfileReopensTheLastOneUsed() {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)

        #expect(store.launchProfileID == nil)
        #expect(ProfileStore(file: file).currentID == work.id)
    }

    /// Deleting the profile the browser was told to open must not leave a
    /// launch pointing at nothing.
    @Test func deletingThePinnedProfileForgetsThePin() async {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.setLaunchProfile(work.id)

        await store.remove(work)
        #expect(store.launchProfileID == nil)

        let reopened = ProfileStore(file: file)
        #expect(reopened.launchProfileID == nil)
        #expect(reopened.current.isOriginal)
    }

    @Test func aNewProfileStartsGrey() {
        let (store, _) = makeStore()

        #expect(store.add(name: "Work").color == .gray)
    }

    @Test func aProfileCanBeDressedAndKeepsIt() throws {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")

        store.setAppearance(of: work, symbol: "briefcase", color: .teal)

        let reopened = try #require(ProfileStore(file: file).profiles.first { $0.id == work.id })
        #expect(reopened.symbol == "briefcase")
        #expect(reopened.color == .teal)
    }

    // MARK: - Private browsing

    /// It is a mode you enter, not one of the profiles you keep, so it must
    /// not appear in the list you can rename and delete.
    @Test func privateBrowsingIsNotOneOfTheKeptProfiles() {
        let (store, _) = makeStore()

        #expect(!store.profiles.contains { $0.isPrivate })
        #expect(!store.deletableProfiles.contains { $0.isPrivate })
        #expect(store.privateBrowsing.isPrivate)
    }

    /// The promise. A file would outlive the session, and the point of the
    /// session is that nothing does.
    @Test func privateBrowsingHasNoDatabaseFile() {
        #expect(Profile.privateBrowsing().databaseURL == nil)
    }

    /// Its stores point somewhere that is neither another profile's files nor
    /// anywhere permanent.
    @Test func privateBrowsingKeepsNothingBesideARealProfile() {
        let priv = Profile.privateBrowsing()

        #expect(priv.supportDirectory != AppDatabase.supportDirectory)
        #expect(priv.zoomFile != Profile.original().zoomFile)
        #expect(priv.permissionsFile != Profile.original().permissionsFile)
    }

    /// A browser that relaunched into private browsing because that is where
    /// it was when it quit would be announcing the session it just forgot.
    @Test func enteringPrivateBrowsingIsNeverWrittenDown() {
        let (store, file) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)

        store.markCurrent(store.privateBrowsing)
        #expect(store.isPrivate)

        let reopened = ProfileStore(file: file)
        #expect(!reopened.isPrivate)
        #expect(reopened.currentID == work.id)
    }

    /// Leaving hands the browser back to where it came from, not to whichever
    /// profile happens to be first.
    @Test func leavingPrivateBrowsingReturnsToTheProfileItCameFrom() {
        let (store, _) = makeStore()
        let work = store.add(name: "Work")
        store.markCurrent(work)
        store.markCurrent(store.privateBrowsing)

        #expect(store.profileToReturnTo.id == work.id)
    }

    /// While private is open, `current` is the private profile - that is what
    /// the chrome and the switcher read.
    @Test func theOpenProfileIsThePrivateOneWhileItLasts() {
        let (store, _) = makeStore()
        store.markCurrent(store.privateBrowsing)

        #expect(store.current.isPrivate)
        #expect(store.current.id == Profile.privateID)
    }

    /// A file naming the private profile - which should never happen, but a
    /// hand-edited or corrupted one could - must not open private browsing.
    @Test func aStoredPrivateChoiceIsRefused() throws {
        let (_, file) = makeStore()
        let json = """
            {"profiles":[],"currentID":"\(Profile.privateID.uuidString)"}
            """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let reopened = ProfileStore(file: file)
        #expect(!reopened.isPrivate)
        #expect(reopened.current.isOriginal)
    }

    /// An unreadable file is a first launch, not a crash.
    @Test func aCorruptFileReadsAsAFirstLaunch() throws {
        let file = URL(filePath: NSTemporaryDirectory())
            .appending(path: "profiles-\(UUID().uuidString).json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)

        let store = ProfileStore(file: file)
        #expect(store.profiles.count == 1)
        #expect(store.current.isOriginal)
    }
}
