// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct ExtensionProfileScopeTests {
    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linen-ext-scope-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeProfile(_ name: String) -> Profile {
        Profile(id: UUID(), name: name, symbol: "person", color: .gray)
    }

    private func library(_ directory: URL, _ profile: Profile) -> ExtensionLibrary {
        let library = ExtensionLibrary(baseDirectory: directory, profile: profile)
        library.load()
        return library
    }

    @Test func anExtensionInstalledInOneProfileIsOffInAnother() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        let personal = library(directory, .original())
        personal.recordInstall(id: "ublock")
        #expect(personal.records.map(\.enabled) == [true])

        let other = library(directory, work)
        #expect(other.records.map(\.id) == ["ublock"])
        #expect(other.records.map(\.enabled) == [false])
    }

    @Test func eachProfileRemembersWhatItTurnedOn() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        library(directory, .original()).recordInstall(id: "ublock")
        let firstVisit = library(directory, work)
        firstVisit.setEnabled(true, id: "ublock")

        let secondVisit = library(directory, work)
        #expect(secondVisit.records.map(\.enabled) == [true])

        let personal = library(directory, .original())
        #expect(personal.records.map(\.enabled) == [true])
    }

    @Test func turningOneOffLeavesTheOtherProfileAlone() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        library(directory, .original()).recordInstall(id: "ublock")
        let workLibrary = library(directory, work)
        workLibrary.setEnabled(true, id: "ublock")
        workLibrary.setEnabled(false, id: "ublock")

        #expect(library(directory, .original()).records.map(\.enabled) == [true])
        #expect(library(directory, work).records.map(\.enabled) == [false])
    }

    @Test func privateBrowsingKeepsItsOwnChoiceBetweenSessions() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        library(directory, .original()).recordInstall(id: "ublock")
        #expect(library(directory, .privateBrowsing()).records.map(\.enabled) == [false])

        library(directory, .privateBrowsing()).setEnabled(true, id: "ublock")
        #expect(library(directory, .privateBrowsing()).records.map(\.enabled) == [true])
    }

    @Test func removingAnExtensionTakesItOutOfEveryProfile() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        library(directory, .original()).recordInstall(id: "ublock")
        library(directory, work).setEnabled(true, id: "ublock")

        library(directory, .original()).uninstall(id: "ublock")

        #expect(library(directory, .original()).records.isEmpty)
        #expect(library(directory, work).records.isEmpty)
    }

    @Test func anOlderIndexBecomesThePersonalProfilesChoices() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
            {"records":[\
            {"id":"ublock","displayName":"uBlock","version":"1","enabled":true,\
            "installedAt":1,"isPinned":true,"toolbarOrder":0}\
            ]}
            """
        try? Data(json.utf8).write(to: directory.appendingPathComponent("installed.json"))

        let personal = library(directory, .original())
        #expect(personal.records.map(\.id) == ["ublock"])
        #expect(personal.records.map(\.enabled) == [true])

        let work = library(directory, makeProfile("Work"))
        #expect(work.records.map(\.enabled) == [false])
    }

    @Test func aProfilesCountIsWhatItTurnedOnNotWhatIsInstalled() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        let personal = library(directory, .original())
        personal.recordInstall(id: "ublock")
        personal.recordInstall(id: "darkreader")

        #expect(ExtensionLibrary.enabledCount(forProfile: Profile.originalID, in: directory) == 2)
        #expect(ExtensionLibrary.enabledCount(forProfile: work.id, in: directory) == 0)

        library(directory, work).setEnabled(true, id: "ublock")
        #expect(ExtensionLibrary.enabledCount(forProfile: work.id, in: directory) == 1)
    }

    @Test func removingAProfileForgetsWhatItHadTurnedOn() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")

        library(directory, .original()).recordInstall(id: "ublock")
        library(directory, work).setEnabled(true, id: "ublock")
        #expect(ExtensionLibrary.enabledCount(forProfile: work.id, in: directory) == 1)

        library(directory, work).forgetThisProfile()

        #expect(ExtensionLibrary.enabledCount(forProfile: work.id, in: directory) == 0)
        #expect(ExtensionLibrary.enabledCount(forProfile: Profile.originalID, in: directory) == 1)
        #expect(library(directory, .original()).records.map(\.id) == ["ublock"])
    }

    @Test func endingAPrivateSessionKeepsItsChoices() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        library(directory, .original()).recordInstall(id: "ublock")
        library(directory, .privateBrowsing()).setEnabled(true, id: "ublock")

        await ExtensionManager.eraseData(for: .privateBrowsing())

        #expect(ExtensionLibrary.enabledCount(forProfile: Profile.privateID, in: directory) == 1)
    }

    @Test func aSafariExtensionIsSwitchedPerProfileToo() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")
        let id = "org.darkreader.DarkReaderSafari.Extension"

        #expect(!library(directory, .original()).placement(for: id).enabled)

        library(directory, work).setEnabled(true, id: id)

        #expect(library(directory, work).placement(for: id).enabled)
        #expect(!library(directory, .original()).placement(for: id).enabled)
        #expect(library(directory, .original()).records.isEmpty)
    }

    @Test func theControllerFollowsTheProfileFromLaunchOnwards() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = makeProfile("Work")
        let browser = BrowserModel(database: .temporary())
        let manager = ExtensionManager(
            browser: browser,
            library: ExtensionLibrary(baseDirectory: directory, profile: work)
        )

        manager.useLibrary(for: .original())
        #expect(manager.controller.configuration.identifier == nil)

        manager.useLibrary(for: work)
        #expect(manager.controller.configuration.identifier == work.id)
        #expect(manager.controller.configuration.isPersistent)

        manager.useLibrary(for: .original())
        #expect(manager.controller.configuration.identifier == nil)
        #expect(manager.controller.configuration.isPersistent)

        manager.useLibrary(for: .privateBrowsing())
        #expect(!manager.controller.configuration.isPersistent)
    }

    @Test func eachProfileStoresItsExtensionDataSomewhereElse() {
        let personal = Profile.original()
        let work = makeProfile("Work")

        let personalStore = ExtensionManager.storageIdentifier(for: personal)
        let workStore = ExtensionManager.storageIdentifier(for: work)
        let privateStore = ExtensionManager.storageIdentifier(for: .privateBrowsing())

        #expect(personalStore != workStore)
        #expect(workStore == .persistent(work.id))
        #expect(privateStore == .ephemeral)
    }
}
