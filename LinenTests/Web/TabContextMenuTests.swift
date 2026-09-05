// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing
import WebKit

@testable import Linen

@MainActor
struct TabContextMenuTests {
    private func menu(_ entries: [String?]) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry, action: nil, keyEquivalent: "")
            item.identifier = entry.hasPrefix("WKMenuItemIdentifier")
                ? NSUserInterfaceItemIdentifier(entry)
                : nil
            menu.addItem(item)
        }
        return menu
    }

    private func marks(_ menu: NSMenu) -> [String] {
        menu.items.map { item in
            if item.isSeparatorItem {
                return "—"
            }
            return item.identifier?.rawValue ?? item.title
        }
    }

    private var linkMenu: NSMenu {
        menu([
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "Open Link in Peek",
            "Summarize Link",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
            nil,
            "WKMenuItemIdentifierInspectElement",
        ])
    }

    @Test func theLinkTailSinksBelowEverythingElse() {
        let menu = linkMenu
        TabContextMenu.sinkLinkTail(in: menu)

        #expect(marks(menu) == [
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "Open Link in Peek",
            "Summarize Link",
            "—",
            "WKMenuItemIdentifierInspectElement",
            "—",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
    }

    @Test func theTailReadsCopyThenShareThenDownload() {
        let menu = menu([
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "WKMenuItemIdentifierDownloadLinkedFile",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierCopyLink",
        ])
        TabContextMenu.sinkLinkTail(in: menu)

        #expect(marks(menu).suffix(3) == [
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
    }

    @Test func inspectElementEndsUpLast() {
        let menu = linkMenu
        TabContextMenu.sinkLinkTail(in: menu)
        TabContextMenu.sinkInspect(in: menu)

        #expect(marks(menu) == [
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "Open Link in Peek",
            "Summarize Link",
            "—",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
            "—",
            "WKMenuItemIdentifierInspectElement",
        ])
    }

    @Test func sinkingInspectTwiceChangesNothing() {
        let menu = linkMenu
        TabContextMenu.sinkInspect(in: menu)
        let once = marks(menu)
        TabContextMenu.sinkInspect(in: menu)

        #expect(marks(menu) == once)
        #expect(marks(menu).filter { $0 == "—" }.count == 1)
    }

    @Test func aMenuWithoutTheseItemsIsLeftAlone() {
        let menu = menu(["Reload Page", nil, "Save Page As…"])
        let before = marks(menu)
        TabContextMenu.sinkLinkTail(in: menu)
        TabContextMenu.sinkInspect(in: menu)

        #expect(marks(menu) == before)
    }

    @Test(.boundedWebViews) func aLinkMenuComesOutOfTheWebViewInThatOrder() throws {
        let view = TabWebView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            configuration: WebViewPool.makeConfiguration()
        )
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let menu = menu([
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
            nil,
            "WKMenuItemIdentifierReload",
            nil,
            "WKMenuItemIdentifierInspectElement",
        ])
        view.willOpenMenu(menu, with: event)

        #expect(menu.items.first?.title == "Open Link in New Tab")
        #expect(marks(menu) == [
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "peekAtContextLink",
            "summarizeContextLink",
            "—",
            "WKMenuItemIdentifierReload",
            "—",
            "savePage",
            "printPage",
            "—",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
            "—",
            "WKMenuItemIdentifierInspectElement",
        ])
    }

    /// The tail is lifted out of the middle of the menu, and the rule that was
    /// holding it apart from what came before goes with it.
    @Test func theRuleTheTailLeavesBehindGoesWithIt() {
        let menu = menu([
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            nil,
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
        TabContextMenu.sinkLinkTail(in: menu)

        #expect(marks(menu) == [
            "WKMenuItemIdentifierOpenLinkInNewWindow",
            "—",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
    }

    @Test func aRunOfRulesLeftBehindGoesTooRatherThanTheLastOfThem() {
        let menu = menu([
            "Reload Page",
            nil,
            nil,
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
        TabContextMenu.sinkLinkTail(in: menu)

        #expect(marks(menu) == [
            "Reload Page",
            "—",
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
    }

    @Test func aMenuOfNothingButTheTailGrowsNoSeparator() {
        let menu = menu([
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
        TabContextMenu.sinkLinkTail(in: menu)

        #expect(marks(menu) == [
            "WKMenuItemIdentifierCopyLink",
            "WKMenuItemIdentifierShareMenu",
            "WKMenuItemIdentifierDownloadLinkedFile",
        ])
    }

    @Test func aMenuOfNothingButTheInspectorGrowsNoSeparator() {
        let menu = menu(["WKMenuItemIdentifierInspectElement"])
        TabContextMenu.sinkInspect(in: menu)

        #expect(marks(menu) == ["WKMenuItemIdentifierInspectElement"])
    }
}
