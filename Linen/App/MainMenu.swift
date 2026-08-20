// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum ShortcutPriority {
    private static let pageFirst: [(key: String, modifiers: NSEvent.ModifierFlags)] = [
        ("z", [.command]),
        ("z", [.command, .shift]),
        ("x", [.command]),
        ("c", [.command]),
        ("v", [.command]),
        ("v", [.command, .option, .shift]),
        ("a", [.command]),
        ("f", [.command]),
        ("g", [.command]),
        ("g", [.command, .shift]),
    ]

    static func menuAnswersFirst(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags.contains(.command) || flags.contains(.control) else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return !pageFirst.contains { $0.key == key && $0.modifiers == flags }
    }
}

@MainActor
final class MainMenu: NSObject, NSMenuItemValidation {
    private let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func install() {
        let root = NSMenu()
        root.addItem(submenu(appMenu(), titled: "Linen"))
        root.addItem(submenu(fileMenu(), titled: "File"))
        root.addItem(submenu(editMenu(), titled: "Edit"))
        root.addItem(submenu(viewMenu(), titled: "View"))
        root.addItem(submenu(historyMenu(), titled: "History"))

        let window = windowMenu()
        root.addItem(submenu(window, titled: "Window"))

        let help = NSMenu(title: "Help")
        root.addItem(submenu(help, titled: "Help"))

        NSApp.mainMenu = root
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
    }

    // MARK: - Menus

    private func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(chain("About Linen", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(command("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(command("Release Notes", #selector(showReleaseNotes)))
        menu.addItem(.separator())
        menu.addItem(command("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services, titled: "Services"))
        NSApp.servicesMenu = services

        menu.addItem(.separator())
        menu.addItem(chain("Hide Linen", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(chain(
            "Hide Others",
            #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(chain("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(chain("Quit Linen", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(command("New Tab", #selector(newTab), key: "t"))
        menu.addItem(hidden(command("New Tab", #selector(newTab), key: "n")))
        menu.addItem(command("Private Browsing", #selector(newPrivateTab), key: "n", modifiers: [.command, .shift]))
        menu.addItem(command("Leave Private Browsing", #selector(leavePrivateBrowsing)))
        menu.addItem(command("Reopen Last Closed Tab", #selector(reopenClosedTab), key: "t", modifiers: [.command, .shift]))
        menu.addItem(command("Close Tab", #selector(closeTab), key: "w"))
        menu.addItem(.separator())
        menu.addItem(command("Bookmark This Page", #selector(pinPage), key: "d"))
        menu.addItem(command("Back to Bookmarked Page", #selector(returnToPin), key: "d", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(command("Open Location…", #selector(openLocation), key: "l"))
        menu.addItem(command("Search Everything…", #selector(openPalette), key: "k"))
        menu.addItem(.separator())
        menu.addItem(command("Downloads", #selector(openDownloads), key: "l", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(chain(
            "Close Window",
            #selector(NSWindow.performClose(_:)),
            key: "w",
            modifiers: [.command, .shift]
        ))
        menu.addItem(command("Print…", #selector(printPage), key: "p"))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(chain("Undo", Selector(("undo:")), key: "z"))
        menu.addItem(chain("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(chain("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(chain("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(chain("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(chain(
            "Paste and Match Style",
            #selector(NSTextView.pasteAsPlainText(_:)),
            key: "v",
            modifiers: [.command, .option, .shift]
        ))
        menu.addItem(chain("Delete", #selector(NSText.delete(_:))))
        menu.addItem(chain("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        menu.addItem(.separator())
        menu.addItem(command("Copy Link", #selector(copyPageURL), key: "c", modifiers: [.command, .shift]))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(command("Find…", #selector(openFind), key: "f"))
        find.addItem(command("Find Next", #selector(findNext), key: "g"))
        find.addItem(command("Find Previous", #selector(findPrevious), key: "g", modifiers: [.command, .shift]))
        menu.addItem(submenu(find, titled: "Find"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(command("Reload Page", #selector(reload), key: "r"))
        menu.addItem(command("Reload Page from Origin", #selector(hardReload), key: "r", modifiers: [.command, .shift]))
        menu.addItem(command("Stop", #selector(stopLoading), key: "."))
        menu.addItem(.separator())
        menu.addItem(command("Actual Size", #selector(actualSize), key: "0"))
        menu.addItem(command("Zoom In", #selector(zoomIn), key: "+"))
        menu.addItem(hidden(command("Zoom In", #selector(zoomIn), key: "=")))
        menu.addItem(command("Zoom Out", #selector(zoomOut), key: "-"))
        menu.addItem(.separator())
        menu.addItem(chain(
            "Enter Full Screen",
            #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.command, .control]
        ))
        menu.addItem(command("Hide Browser", #selector(toggleBrowser), key: "b", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(submenu(splitViewMenu(), titled: "Split View"))
        menu.addItem(.separator())
        menu.addItem(command("Hide Sidebar", #selector(toggleSidebar), key: "s", modifiers: [.command, .control]))
        menu.addItem(command(
            "Show Agent Activity",
            #selector(toggleAgentInspector),
            key: "a",
            modifiers: [.command, .option]
        ))
        return menu
    }

    private func splitViewMenu() -> NSMenu {
        let menu = NSMenu()
        let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let downArrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        menu.addItem(command("Split Right", #selector(splitRight), key: rightArrow, modifiers: [.command, .control]))
        menu.addItem(command("Split Down", #selector(splitDown), key: downArrow, modifiers: [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(command("Other Pane", #selector(focusOtherPane), key: "]", modifiers: [.command, .option]))
        menu.addItem(command("Swap Panes", #selector(swapPanes)))
        menu.addItem(command("Stack Pages", #selector(toggleSplitAxis)))
        menu.addItem(.separator())
        menu.addItem(command("Exit Split", #selector(exitSplit)))
        menu.addItem(command("Close Other Pages", #selector(closeOtherPanes)))
        return menu
    }

    private func historyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(command("Back", #selector(goBack), key: "["))
        menu.addItem(command("Forward", #selector(goForward), key: "]"))
        menu.addItem(hidden(command("Back", #selector(goBack), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!))))
        menu.addItem(hidden(command("Forward", #selector(goForward), key: String(UnicodeScalar(NSRightArrowFunctionKey)!))))
        menu.addItem(.separator())
        menu.addItem(command("Show All History", #selector(showHistory), key: "y"))
        menu.addItem(command("Clear History…", #selector(clearHistory)))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(chain("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(chain("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(command("Show Next Tab", #selector(nextTab), key: "]", modifiers: [.command, .shift]))
        menu.addItem(command("Show Previous Tab", #selector(previousTab), key: "[", modifiers: [.command, .shift]))
        menu.addItem(hidden(command("Show Next Tab", #selector(switchToNextTab), key: "\t", modifiers: [.control])))
        menu.addItem(hidden(command(
            "Show Previous Tab",
            #selector(switchToPreviousTab),
            key: "\t",
            modifiers: [.control, .shift]
        )))
        menu.addItem(.separator())
        for slot in 1...8 {
            menu.addItem(hidden(command("Show Tab \(slot)", #selector(showTabAtIndex(_:)), key: "\(slot)")))
            menu.items.last?.tag = slot - 1
        }
        menu.addItem(hidden(command("Show Last Tab", #selector(showLastTab), key: "9")))
        menu.addItem(.separator())
        menu.addItem(chain("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: - Commands

    @objc private func openSettings() {
        coordinator.openSettings()
    }

    @objc private func checkForUpdates() {
        coordinator.openSettings(.about)
        coordinator.updates.checkNow()
    }
    @objc private func showReleaseNotes() {
        coordinator.showReleaseNotes()
    }

    @objc private func openDownloads() {
        coordinator.openSettings(.downloads)
    }
    @objc private func newTab() {
        coordinator.openNewTab()
    }
    @objc private func newPrivateTab() {
        coordinator.enterPrivateBrowsing()
    }
    @objc private func leavePrivateBrowsing() {
        coordinator.leavePrivateBrowsing()
    }
    @objc private func closeTab() {
        coordinator.browser.closeActiveTab()
    }
    @objc private func reopenClosedTab() {
        coordinator.browser.reopenLastClosedTab()
        coordinator.showBrowserPage()
    }
    @objc private func openLocation() {
        coordinator.focusAddressBar()
    }
    @objc private func copyPageURL() {
        coordinator.copyCurrentURL()
    }

    @objc private func pinPage() {
        coordinator.togglePin()
    }

    @objc private func returnToPin() {
        guard let tab = coordinator.browser.activeTab else { return }
        coordinator.browser.returnToPin(tab)
    }
    @objc private func openPalette() {
        coordinator.togglePalette()
    }
    @objc private func showHistory() {
        coordinator.showHistory()
    }
    @objc private func reload() {
        activeWebView?.reload()
    }
    @objc private func hardReload() {
        activeWebView?.reloadFromOrigin()
    }
    @objc private func stopLoading() {
        activeWebView?.stopLoading()
    }
    @objc private func goBack() {
        coordinator.browser.activeTab?.goBack()
    }
    @objc private func goForward() {
        coordinator.browser.activeTab?.goForward()
    }
    @objc private func toggleBrowser() {
        coordinator.toggleBrowser()
    }
    @objc private func toggleSidebar() {
        coordinator.toggleSidebar()
    }
    @objc private func toggleAgentInspector() {
        coordinator.toggleAgentInspector()
    }

    @objc private func splitRight() {
        coordinator.splitActiveTab(axis: .sideBySide)
    }
    @objc private func splitDown() {
        coordinator.splitActiveTab(axis: .stacked)
    }
    @objc private func focusOtherPane() {
        coordinator.focusOtherPane()
    }
    @objc private func swapPanes() {
        coordinator.swapSplitPanes()
    }
    @objc private func toggleSplitAxis() {
        coordinator.toggleSplitAxis()
    }
    @objc private func exitSplit() {
        coordinator.exitSplit()
    }
    @objc private func closeOtherPanes() {
        coordinator.closeOtherPanes()
    }

    @objc private func openFind() {
        coordinator.browser.activeTab?.find.open()
    }
    @objc private func findNext() {
        coordinator.browser.activeTab?.find.findNext(backwards: false)
    }
    @objc private func findPrevious() {
        coordinator.browser.activeTab?.find.findNext(backwards: true)
    }

    @objc private func nextTab() {
        coordinator.browser.cycleTab(forward: true)
        coordinator.showBrowserPage()
    }
    @objc private func previousTab() {
        coordinator.browser.cycleTab(forward: false)
        coordinator.showBrowserPage()
    }
    @objc private func switchToNextTab() {
        coordinator.browser.switchTab(forward: true, asTap: coordinator.isControlTap)
        coordinator.showBrowserPage()
    }
    @objc private func switchToPreviousTab() {
        coordinator.browser.switchTab(forward: false)
        coordinator.showBrowserPage()
    }
    @objc private func showTabAtIndex(_ sender: NSMenuItem) {
        coordinator.browser.activateTab(at: sender.tag)
        coordinator.showBrowserPage()
    }
    @objc private func showLastTab() {
        coordinator.browser.activateLastTab()
        coordinator.showBrowserPage()
    }

    @objc private func clearHistory() {
        coordinator.confirmClearHistory()
    }

    @objc private func printPage() {
        coordinator.printActivePage()
    }

    @objc private func actualSize() {
        coordinator.browser.activeTab?.resetZoom()
    }
    @objc private func zoomIn() {
        coordinator.browser.activeTab?.zoomIn()
    }
    @objc private func zoomOut() {
        coordinator.browser.activeTab?.zoomOut()
    }

    private var activeWebView: WKWebView? {
        coordinator.browser.activeTab?.webView
    }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {  // swiftlint:disable:this cyclomatic_complexity
        switch menuItem.action {
        case #selector(goBack):
            return coordinator.browser.activeTab?.canGoBack ?? false
        case #selector(goForward):
            return coordinator.browser.activeTab?.canGoForward ?? false
        case #selector(actualSize):
            return coordinator.browser.activeTab?.isZoomed ?? false
        case #selector(reload), #selector(hardReload), #selector(closeTab),
             #selector(zoomIn), #selector(zoomOut), #selector(openFind), #selector(findNext),
             #selector(findPrevious), #selector(printPage):
            return coordinator.browser.activeTab != nil
        case #selector(stopLoading):
            return coordinator.browser.activeTab?.isLoading ?? false
        case #selector(splitRight), #selector(splitDown):
            guard coordinator.browser.activeTab != nil else { return false }
            return !(coordinator.browser.activeSplit?.isFull ?? false)
        case #selector(focusOtherPane), #selector(exitSplit), #selector(closeOtherPanes):
            return coordinator.isSplit
        case #selector(swapPanes):
            guard let split = coordinator.browser.activeSplit,
                  let id = coordinator.browser.activeTabID
            else { return false }
            return split.sibling(of: id) != nil
        case #selector(toggleSplitAxis):
            let axisTitle: LocalizedStringResource = coordinator.browser.activeSplit?.axis == .stacked
                ? "Place Side by Side"
                : "Stack Pages"
            menuItem.title = String(localized: axisTitle)
            return coordinator.browser.activeSplit?.axis != nil
        case #selector(reopenClosedTab):
            return coordinator.browser.canReopenClosedTab
        case #selector(leavePrivateBrowsing):
            return coordinator.profiles.isPrivate
        case #selector(nextTab), #selector(previousTab), #selector(showLastTab),
             #selector(switchToNextTab), #selector(switchToPreviousTab):
            return coordinator.browser.tabs.count > 1
        case #selector(showTabAtIndex(_:)):
            return coordinator.browser.tabs.indices.contains(menuItem.tag)
        case #selector(clearHistory):
            return coordinator.browser.history.count > 0
        case #selector(checkForUpdates):
            return coordinator.updates.canCheck
        case #selector(toggleBrowser):
            let browserTitle: LocalizedStringResource = coordinator.browserVisible
                ? "Hide Browser" : "Show Browser"
            menuItem.title = String(localized: browserTitle)
            return true
        case #selector(toggleSidebar):
            let sidebarTitle: LocalizedStringResource = coordinator.sidebar.isVisible
                ? "Hide Sidebar" : "Show Sidebar"
            menuItem.title = String(localized: sidebarTitle)
            return true
        case #selector(toggleAgentInspector):
            let activityTitle: LocalizedStringResource = coordinator.agentInspector.isVisible
                ? "Hide Agent Activity"
                : "Show Agent Activity"
            menuItem.title = String(localized: activityTitle)
            return true
        default:
            return true
        }
    }

    // MARK: - Building blocks

    private func submenu(_ menu: NSMenu, titled title: LocalizedStringResource) -> NSMenuItem {
        let name = String(localized: title)
        let holder = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        menu.title = name
        holder.submenu = menu
        return holder
    }

    private func command(
        _ title: LocalizedStringResource,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = makeItem(title, action, key: key, modifiers: modifiers)
        item.target = self
        return item
    }

    private func chain(
        _ title: LocalizedStringResource,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        makeItem(title, action, key: key, modifiers: modifiers)
    }

    private func makeItem(
        _ title: LocalizedStringResource,
        _ action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        var key = key
        var modifiers = modifiers
        if modifiers.contains(.shift), key.count == 1, key >= "a", key <= "z" {
            key = key.uppercased()
            modifiers.remove(.shift)
        }
        let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    private func hidden(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.isAlternate = false
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }
}
