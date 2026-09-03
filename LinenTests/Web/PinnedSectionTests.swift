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
        model.settlePins([.tab(loose.id)])

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
        model.settlePins([.tab(other.id)])

        #expect(other.pinnedURL == nil)
        #expect(kept.pinnedURL != nil)
        #expect(order(model).last == "https://other.example/")
        #expect(loose.pinnedURL == nil)
    }

    /// With no pinned tab left there is no section to drop into, so the top of
    /// the list is just the top of the list.
    @Test func theTopOfAnUnpinnedListDoesNotPin() {
        let model = model()
        let first = tab("https://one.example/", in: model)
        let second = tab("https://two.example/", in: model)

        model.move([.tab(second.id)], into: nil, before: .tab(first.id))
        model.settlePins([.tab(second.id)])

        #expect(second.pinnedURL == nil)
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
        model.settlePins([.tab(blank.id)])

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
