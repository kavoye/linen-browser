// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

extension AppCoordinator {
    /// The panel is only on screen over the page it was opened from.
    var isPeekOnScreen: Bool {
        guard !peek.isCollapsed, let owner = peek.ownerID else { return false }
        return browser.activeTabID == owner || browser.activeSplit?.contains(owner) == true
    }

    var shownPeek: BrowserTab? {
        isPeekOnScreen ? peek.tab : nil
    }

    var pageCommandTab: BrowserTab? {
        shownPeek ?? browser.activeTab
    }

    func togglePeekVisibility() {
        guard let ownerID = peek.ownerID, let owner = browser.tab(id: ownerID) else { return }
        let collapse = shownPeek != nil
        tabPreview.dismiss()
        if !collapse {
            browser.activate(owner)
        }
        peek.setCollapsed(collapse)
        applyHoverShield()
    }

    func openPeek(url: URL, from owner: BrowserTab?, at origin: CGPoint) {
        linkPeek.forget()
        showBrowser()
        if let standing = peek.tab, peek.ownerID == owner?.id {
            peek.aim(at: origin)
            standing.load(url, transition: .link)
            applyHoverShield()
            return
        }
        closePeek()
        peek.show(browser.makePeekTab(url), from: owner?.id, at: origin)
        applyHoverShield()
    }

    @discardableResult
    func closePeek() -> Bool {
        guard peek.dismiss(using: browser) else { return false }
        applyHoverShield()
        return true
    }

    func closePeekImmediately() {
        peek.dismissImmediately(using: browser)
        applyHoverShield()
    }

    func keepPeek() {
        guard let tab = peek.take(quietly: true) else { return }
        browser.keepPeekTab(tab, after: browser.activeTab)
        applyHoverShield()
    }

    func keepPeekBesideCurrentPage() {
        guard let anchor = browser.activeTab, let tab = peek.take(quietly: true) else { return }
        browser.keepPeekTab(tab, besidePage: anchor)
        applyHoverShield()
    }
}
