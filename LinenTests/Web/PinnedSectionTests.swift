// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Where a tab sits decides whether it is pinned: the run at the top of the
/// sidebar is the pinned section, and a tab takes its pin from landing there.
@MainActor
struct PinnedSectionTests {
    private func model() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    private func tab(_ address: String, in model: BrowserModel) -> BrowserTab {
        let tab = model.newTab(url: URL(string: address))
        tab.urlString = address
        return tab
    }

    private func order(_ model: BrowserModel) -> [String] {
        model.rows(in: nil).compactMap { item in
            guard case .tab(let id) = item else { return nil }
            return model.tab(id: id)?.urlString
        }
    }

    @Test func pinningMovesTheTabToTheEndOfThePinnedRun() {
        let model = model()
        let first = tab("https://one.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let second = tab("https://two.example/", in: model)
        model.pin(first)
        model.pin(second)

        #expect(order(model) == [
            "https://one.example/",
            "https://two.example/",
            "https://loose.example/",
        ])
        #expect(loose.pinnedURL == nil)
    }

    @Test func aTabDroppedIntoThePinnedSectionIsPinned() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        model.pin(kept)

        model.move([.tab(loose.id)], into: nil, before: .tab(kept.id))
        model.setPinned(true, for: [.tab(loose.id)])

        #expect(loose.pinnedURL?.absoluteString == "https://loose.example/")
    }

    @Test func aPinnedTabDroppedBelowTheSectionIsUnpinned() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let other = tab("https://other.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        model.pin(kept)
        model.pin(other)

        model.move([.tab(other.id)], into: nil, before: nil)
        model.setPinned(false, for: [.tab(other.id)])

        #expect(other.pinnedURL == nil)
        #expect(kept.pinnedURL != nil)
        #expect(order(model).last == "https://other.example/")
        #expect(loose.pinnedURL == nil)
    }

    @Test func takingThePinLeavesTheOrderAlone() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let last = tab("https://last.example/", in: model)
        model.pin(kept)

        model.move([.tab(last.id)], into: nil, before: .tab(loose.id))
        model.setPinned(false, for: [.tab(last.id)])

        #expect(last.pinnedURL == nil)
        #expect(order(model) == [
            "https://kept.example/",
            "https://last.example/",
            "https://loose.example/",
        ])
    }

    @Test func theShelfStartsASectionAnUnpinnedListHasNot() {
        let model = model()
        let first = tab("https://one.example/", in: model)
        let second = tab("https://two.example/", in: model)

        model.pinAtTop([.tab(second.id)])

        #expect(second.pinnedURL?.absoluteString == "https://two.example/")
        #expect(first.pinnedURL == nil)
        #expect(order(model) == ["https://two.example/", "https://one.example/"])
    }

    @Test func theShelfLandsUnderTheTabsAlreadyKept() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let other = tab("https://other.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        model.pin(kept)
        model.pin(other)

        model.pinAtTop([.tab(loose.id)])

        #expect(loose.pinnedURL?.absoluteString == "https://loose.example/")
        #expect(order(model) == [
            "https://kept.example/",
            "https://other.example/",
            "https://loose.example/",
        ])
    }

    @Test func theShelfCannotPinATabWithNoPage() {
        let model = model()
        _ = tab("https://one.example/", in: model)
        let blank = model.newTab()

        model.pinAtTop([.tab(blank.id)])

        #expect(blank.pinnedURL == nil)
    }

    // MARK: - Folders

    @Test func aFolderIsKeptOnlyWhileEverythingInItIs() {
        let model = model()
        let one = tab("https://one.example/", in: model)
        let two = tab("https://two.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [one, two])

        #expect(!model.isKept(.folder(folder.id)))

        model.setPinned(true, for: [.folder(folder.id)])

        #expect(one.pinnedURL != nil)
        #expect(two.pinnedURL != nil)
        #expect(model.isKept(.folder(folder.id)))

        model.setPinned(false, for: [.tab(two.id)])

        #expect(!model.isKept(.folder(folder.id)))
    }

    @Test func anEmptyFolderIsNotKept() {
        let model = model()
        let folder = model.createFolder(named: "Work")

        #expect(model.rows(in: folder).isEmpty)
        #expect(!model.isKept(.folder(folder.id)))
        #expect(model.keptRunAtTop().isEmpty)
    }

    @Test func aPinnedTabBelowALooseOneIsNotInTheRun() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let below = tab("https://below.example/", in: model)
        model.pin(kept)
        model.move([.tab(below.id)], into: nil, before: nil)
        model.setPinned(true, for: [.tab(below.id)])

        #expect(order(model) == [
            "https://kept.example/",
            "https://loose.example/",
            "https://below.example/",
        ])
        #expect(below.pinnedURL != nil)
        #expect(model.keptRunAtTop() == [.tab(kept.id)])
    }

    @Test func theShelfPinsEveryTabAFolderHolds() {
        let model = model()
        let one = tab("https://one.example/", in: model)
        let two = tab("https://two.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [one, two])

        model.pinAtTop([.folder(folder.id)])

        #expect(one.pinnedURL != nil)
        #expect(two.pinnedURL != nil)
        #expect(loose.pinnedURL == nil)
        #expect(model.keptRunAtTop() == [.folder(folder.id)])
    }

    @Test func takingAFolderOutOfTheSectionUnpinsWhatItHolds() {
        let model = model()
        let one = tab("https://one.example/", in: model)
        let two = tab("https://two.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [one, two])
        model.pinAtTop([.folder(folder.id)])

        model.setPinned(false, for: [.folder(folder.id)])

        #expect(one.pinnedURL == nil)
        #expect(two.pinnedURL == nil)
        #expect(model.keptRunAtTop().isEmpty)
    }

    @Test func aKeptFolderTakesInWhatIsDroppedIntoIt() {
        let model = model()
        let held = tab("https://held.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [held])
        model.pinAtTop([.folder(folder.id)])

        let keeps = model.isKept(.folder(folder.id), ignoring: [.tab(loose.id)])
        model.move([.tab(loose.id)], into: folder)
        if keeps {
            model.setPinned(true, for: [.tab(loose.id)])
        }

        #expect(keeps)
        #expect(loose.pinnedURL?.absoluteString == "https://loose.example/")
        #expect(model.isKept(.folder(folder.id)))
    }

    @Test func aFolderIgnoresTheRowsInTheAirWhenItAnswers() {
        let model = model()
        let held = tab("https://held.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [held, loose])
        model.setPinned(true, for: [.tab(held.id)])

        #expect(!model.isKept(.folder(folder.id)))
        #expect(model.isKept(.folder(folder.id), ignoring: [.tab(loose.id)]))
        #expect(!model.isKept(.folder(folder.id), ignoring: [.tab(held.id)]))
    }

    @Test func reorderingInsideAKeptFolderKeepsThePins() {
        let model = model()
        let one = tab("https://one.example/", in: model)
        let two = tab("https://two.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [one, two])
        model.pinAtTop([.folder(folder.id)])

        model.move([.tab(two.id)], into: folder, before: .tab(one.id))

        #expect(one.pinnedURL != nil)
        #expect(two.pinnedURL != nil)
        #expect(model.isKept(.folder(folder.id)))
        #expect(model.tabs(in: folder).map(\.urlString) == [
            "https://two.example/",
            "https://one.example/",
        ])
    }

    @Test func aKeptFolderHoldsItsPlaceWhileAnUnpinnedRowIsInTheAir() {
        let model = model()
        let held = tab("https://held.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [held])
        model.pinAtTop([.folder(folder.id)])

        model.move([.tab(loose.id)], into: folder)

        #expect(!model.isKept(.folder(folder.id)))
        #expect(model.isKept(.folder(folder.id), ignoring: [.tab(loose.id)]))
    }

    @Test func aDragKeepsThePinsItIsCarrying() {
        let model = model()
        let held = tab("https://held.example/", in: model)
        let moving = tab("https://moving.example/", in: model)
        let folder = model.createFolder(named: "Work", containing: [held])
        model.pinAtTop([.folder(folder.id)])
        model.pinAtTop([.tab(moving.id)])

        model.move([.tab(moving.id)], into: folder, settlingPins: false)

        #expect(moving.pinnedURL?.absoluteString == "https://moving.example/")
        #expect(model.isKept(.folder(folder.id)))
    }

    @Test func foldingTwoKeptTabsMakesAKeptFolder() {
        let model = model()
        let one = tab("https://one.example/", in: model)
        let two = tab("https://two.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        model.pinAtTop([.tab(one.id)])
        model.pinAtTop([.tab(two.id)])

        let gathered: [SidebarItem] = [.tab(one.id), .tab(two.id)]
        let folder = model.createFolder(named: "Work", containing: gathered)
        model.setPinned(true, for: gathered)

        #expect(model.isKept(.folder(folder.id)))
        #expect(model.keptRunAtTop() == [.folder(folder.id)])
        #expect(loose.pinnedURL == nil)
    }

    @Test func filingAPinnedTabInAFolderUnpinsIt() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        model.pin(kept)
        let folder = model.createFolder(named: "Reading")

        model.move([.tab(kept.id)], into: folder)

        #expect(kept.pinnedURL == nil)
    }

    @Test func aTabWithNoPageCannotBePinnedByADrop() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        model.pin(kept)
        let blank = model.newTab()

        model.move([.tab(blank.id)], into: nil, before: .tab(kept.id))
        model.setPinned(true, for: [.tab(blank.id)])

        #expect(blank.pinnedURL == nil)
    }

    @Test func editingThePinKeepsTheTabInTheSection() {
        let model = model()
        let kept = tab("https://kept.example/", in: model)
        let loose = tab("https://loose.example/", in: model)
        model.pin(kept)

        model.setPin(URL(string: "https://kept.example/inbox")!, for: kept)

        #expect(kept.pinnedURL?.absoluteString == "https://kept.example/inbox")
        #expect(order(model).first == "https://kept.example/")
        #expect(loose.pinnedURL == nil)
    }
}

/// A name you type stays on the tab until the tab closes, whatever the page
/// calls itself afterwards.
@MainActor
struct TabRenameTests {
    private func model() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    @Test func aRenamedTabKeepsItsNameWhenThePageTitleChanges() {
        let model = model()
        let tab = model.newTab()
        tab.pageTitle = "Speed test"

        model.renameTab(tab, to: "Speed")
        tab.pageTitle = "Speedtest by Ookla"

        #expect(tab.title == "Speed")
    }

    @Test func anEmptyNameGivesThePageItsTitleBack() {
        let model = model()
        let tab = model.newTab()
        tab.pageTitle = "Speed test"
        model.renameTab(tab, to: "Speed")

        model.renameTab(tab, to: "   ")

        #expect(tab.title == "Speed test")
        #expect(tab.customTitle.isEmpty)
    }

    @Test func typingThePageTitleBackIsNotACustomName() {
        let model = model()
        let tab = model.newTab()
        tab.pageTitle = "Speed test"

        model.renameTab(tab, to: "Speed test")

        #expect(tab.customTitle.isEmpty)
    }

    @Test func aDuplicateCarriesTheName() {
        let model = model()
        let tab = model.newTab(url: URL(string: "https://one.example/"))
        tab.urlString = "https://one.example/"
        tab.pageTitle = "One"
        model.renameTab(tab, to: "Mine")

        let copy = model.duplicate(tab)

        #expect(copy.title == "Mine")
    }
}
