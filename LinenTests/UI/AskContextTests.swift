// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
struct AskContextTests {
    private func makeModel() -> BrowserModel {
        BrowserModel(
            database: .temporary(),
            sitePermissions: SitePermissions(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("AskContext-\(UUID().uuidString).json")
            )
        )
    }

    @Test func onlyThePageOnScreenIsReadable() {
        let model = makeModel()
        let other = model.newTab(url: URL(string: "https://other.example/b"))
        other.title = "Other"
        let active = model.newTab(url: URL(string: "https://example.com/a"))
        active.title = "Active"
        model.activate(active)

        let pages = AskContext.pages(browser: model, mentionedTabIDs: [])

        #expect(pages.map(\.title) == ["Active"])
        #expect(pages.map(\.host) == ["example.com"])
        #expect(pages.allSatisfy { !$0.isAttached })
    }

    @Test func bothPanesOfASplitAreReadableInPaneOrder() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        left.title = "Left"
        let right = model.newTab(url: URL(string: "https://other.example/b"))
        right.title = "Right"
        model.split(left, with: right, axis: .sideBySide)

        let pages = AskContext.pages(browser: model, mentionedTabIDs: [])

        #expect(pages.map(\.title) == ["Left", "Right"])
    }

    @Test func attachedTabsFollowTheOnScreenOnesAndAreMarked() {
        let model = makeModel()
        let attached = model.newTab(url: URL(string: "https://other.example/b"))
        attached.title = "Attached"
        let active = model.newTab(url: URL(string: "https://example.com/a"))
        active.title = "Active"
        model.activate(active)

        let pages = AskContext.pages(browser: model, mentionedTabIDs: [attached.id])

        #expect(pages.map(\.title) == ["Active", "Attached"])
        #expect(pages.map(\.isAttached) == [false, true])
    }

    @Test func aPaneThatIsAlsoAttachedIsListedOnce() {
        let model = makeModel()
        let left = model.newTab(url: URL(string: "https://example.com/a"))
        left.title = "Left"
        let right = model.newTab(url: URL(string: "https://other.example/b"))
        right.title = "Right"
        model.split(left, with: right, axis: .sideBySide)

        let pages = AskContext.pages(browser: model, mentionedTabIDs: [right.id])

        #expect(pages.map(\.title) == ["Left", "Right"])
        #expect(pages.allSatisfy { !$0.isAttached })
    }
}
