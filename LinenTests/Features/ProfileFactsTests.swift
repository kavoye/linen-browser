// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import GRDB
import Testing

@testable import Linen

/// What a profile's own page says it is holding. The numbers come from the
/// profile's files rather than from the running browser, so they have to be
/// readable for a profile nobody has opened - and reading one must not bring
/// its storage into existence.
@MainActor
struct ProfileFactsTests {
    private func sandbox() -> URL {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "facts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sources(
        in root: URL,
        database: URL? = nil,
        profileID: UUID = Profile.originalID
    ) -> ProfileFacts.Sources {
        ProfileFacts.Sources(
            database: database,
            profileID: profileID,
            extensionLibrary: root.appending(path: "Extensions", directoryHint: .isDirectory),
            permissions: root.appending(path: "SitePermissions.json"),
            support: root,
            holdsOtherProfiles: false
        )
    }

    @Test func aProfileThatWasNeverOpenedReadsAsEmptyAndStaysThatWay() {
        let root = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appending(path: "Profiles/\(UUID().uuidString)/Linen.sqlite")

        let facts = ProfileFacts.read(sources(in: root, database: database))

        #expect(facts == .empty)
        #expect(!FileManager.default.fileExists(atPath: database.deletingLastPathComponent().path))
    }

    @Test func tabsAndPagesAreCountedInTheProfilesOwnDatabase() throws {
        let root = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Linen.sqlite")
        let database = AppDatabase(at: url)
        let history = HistoryStore(database: database)
        _ = history.record(url: "https://example.com/one", title: "One")
        _ = history.record(url: "https://example.com/two", title: "Two")
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessionTab (id, title, url, isActive)
                VALUES (?, 'One', 'https://example.com/one', 1)
                """,
                arguments: [UUID().uuidString]
            )
        }

        let facts = ProfileFacts.read(sources(in: root, database: url))

        #expect(facts.tabs == 1)
        #expect(facts.pages == 2)
        #expect(facts.firstVisit != nil)
        #expect(facts.bytes > 0)
    }

    @Test func onlyWebsitesWithASavedAnswerAreCounted() async throws {
        let root = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "SitePermissions.json")
        let permissions = SitePermissions(storageURL: file)
        permissions.set(.allow, for: "https://example.com", .camera)
        permissions.set(.deny, for: "https://example.com", .microphone)
        permissions.set(.deny, for: "https://maps.example", .location)
        permissions.setAssistantAccess(.readOnly, for: "https://notes.example")
        permissions.setAutoplay(.block, for: "https://video.example")
        permissions.setPopups(.allow, for: "https://ads.example")
        await permissions.waitForPendingSave()

        #expect(SitePermissions.changedSiteCount(in: file) == 5)
    }

    @Test func readingAProfileNobodyOpenedNeverTouchesTheOpenOne() {
        let root = sandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        let facts = ProfileFacts.read(sources(in: root))

        #expect(facts.extensions == 0)
        #expect(facts.permissionSites == 0)
    }
}

@MainActor
struct ProfileLastUsedTests {
    private func makeStore() -> (ProfileStore, URL) {
        let file = URL(filePath: NSTemporaryDirectory())
            .appending(path: "profiles-\(UUID().uuidString).json")
        return (ProfileStore(file: file), file)
    }

    @Test func openingAProfileStampsIt() {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        let work = store.add(name: "Work")

        #expect(store.lastUsed[work.id] == nil)
        store.markCurrent(work)
        #expect(store.lastUsed[work.id] != nil)

        let reopened = ProfileStore(file: file)
        #expect(reopened.lastUsed[work.id] != nil)
    }

    @Test func privateBrowsingIsNeverStamped() {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }

        store.markCurrent(store.privateBrowsing)

        #expect(store.lastUsed[Profile.privateID] == nil)
    }

    @Test func aDeletedProfileTakesItsDateWithIt() async {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        let work = store.add(name: "Work")
        store.markCurrent(work)

        await store.remove(work)

        #expect(store.lastUsed[work.id] == nil)
        #expect(ProfileStore(file: file).lastUsed.isEmpty)
    }
}

@MainActor
struct ProfileAppearanceTests {
    @Test func everyOfferedSymbolExists() {
        let missing = ProfileAppearance.symbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func theGridFillsWholeRows() {
        #expect(ProfileAppearance.symbols.count % 16 == 0)
        #expect(Set(ProfileAppearance.symbols).count == ProfileAppearance.symbols.count)
    }

    @Test func theDefaultSymbolIsOffered() {
        #expect(ProfileAppearance.symbols.contains(ProfileAppearance.defaultSymbol))
    }
}
