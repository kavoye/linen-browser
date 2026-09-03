// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

/// A peeked page is a tab no list holds until you keep it.
@MainActor
struct PeekTests {
    private func model() -> BrowserModel {
        BrowserModel(database: .temporary())
    }

    private let address = URL(string: "https://peeked.example/")!

    @Test func aPeekedPageIsNotInTheSidebar() {
        let model = model()
        let open = model.newTab(url: URL(string: "https://one.example/"))

        let peeked = model.makePeekTab(address)

        #expect(model.tabs.count == 1)
        #expect(model.tabs.first === open)
        #expect(model.tab(id: peeked.id) == nil)
        #expect(model.rows(in: nil).count == 1)
    }

    @Test func keepingAPeekPutsItUnderThePageYouCameFrom() {
        let model = model()
        let opener = model.newTab(url: URL(string: "https://one.example/"))
        opener.urlString = "https://one.example/"
        let older = model.newTab(url: URL(string: "https://older.example/"))
        older.urlString = "https://older.example/"
        model.activate(opener)

        let peeked = model.makePeekTab(address)
        model.keepPeekTab(peeked, after: opener)

        #expect(model.tab(id: peeked.id) === peeked)
        #expect(model.activeTabID == peeked.id)
        let order = model.rows(in: nil).compactMap { item -> String? in
            guard case .tab(let id) = item else { return nil }
            return model.tab(id: id)?.urlString
        }
        #expect(order.firstIndex(of: "https://peeked.example/")
            == order.firstIndex(of: "https://one.example/").map { $0 + 1 })
    }

    @Test func aKeptPeekLandsUnderThePinnedRun() {
        let model = model()
        let kept = model.newTab(url: URL(string: "https://kept.example/"))
        kept.urlString = "https://kept.example/"
        model.pin(kept)

        let peeked = model.makePeekTab(address)
        model.keepPeekTab(peeked, after: kept)

        let order = model.rows(in: nil).compactMap { item -> UUID? in
            guard case .tab(let id) = item else { return nil }
            return id
        }
        #expect(order == [kept.id, peeked.id])
        #expect(peeked.pinnedURL == nil)
    }

    @Test func dismissingAPeekLeavesTheListAlone() {
        let model = model()
        let open = model.newTab(url: URL(string: "https://one.example/"))

        let peeked = model.makePeekTab(address)
        model.dismissPeekTab(peeked)

        #expect(model.tabs.count == 1)
        #expect(model.tabs.first === open)
        #expect(peeked.isClosed)
    }

    /// A peek inside a peek would have nowhere to go, so Shift there is an
    /// ordinary click.
    @Test func aPeekDoesNotPeekAgain() {
        let model = model()
        let peeked = model.makePeekTab(address)

        #expect(peeked.onOpenInPeek == nil)
        #expect(model.newTab().onOpenInPeek != nil)
    }

    @Test func theHeldPeekIsHandedOverOnlyOnce() {
        let panel = PeekPanel()
        let model = model()
        let peeked = model.makePeekTab(address)

        panel.show(peeked, from: UUID(), at: .zero)
        #expect(panel.isOpen)
        #expect(panel.take() === peeked)
        #expect(!panel.isOpen)
        #expect(panel.take() == nil)
    }

    /// The peek belongs to the page it was opened from: leaving that page hides
    /// the panel, it does not throw the page away.
    @Test func aPeekStaysWithThePageItCameFrom() {
        let panel = PeekPanel()
        let model = model()
        let owner = model.newTab(url: URL(string: "https://one.example/"))
        let other = model.newTab(url: URL(string: "https://two.example/"))
        let peeked = model.makePeekTab(address)

        panel.show(peeked, from: owner.id, at: CGPoint(x: 40, y: 60))

        #expect(panel.belongs(to: owner.id))
        #expect(!panel.belongs(to: other.id))
        #expect(panel.isOpen)
        #expect(panel.origin == CGPoint(x: 40, y: 60))
    }

    /// Keeping a peek hands its page to the window behind, so the panel must
    /// not animate away over it.
    @Test func aKeptPeekLeavesWithoutAnimating() {
        let panel = PeekPanel()
        let model = model()
        let peeked = model.makePeekTab(address)

        panel.show(peeked, from: UUID(), at: .zero)
        #expect(!panel.isQuiet)
        _ = panel.take(quietly: true)
        #expect(panel.isQuiet)

        panel.show(model.makePeekTab(address), from: UUID(), at: .zero)
        #expect(!panel.isQuiet)
    }
}

@MainActor
struct LinkIntentTests {
    @Test func shiftReadsAsAPeek() {
        #expect(LinkIntent.of(.shift) == .peek)
    }

    @Test func commandReadsAsANewTabEvenWithShift() {
        #expect(LinkIntent.of(.command) == .newTab)
        #expect(LinkIntent.of([.command, .shift]) == .newTab)
    }

    @Test func otherKeysAreAnOrdinaryOpen() {
        #expect(LinkIntent.of([]) == .open)
        #expect(LinkIntent.of(.option) == .open)
        #expect(LinkIntent.of([.control, .capsLock]) == .open)
    }
}
