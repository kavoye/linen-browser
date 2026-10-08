// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum ShortcutPriority {
    private static let leftArrow = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    private static let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)

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
        (leftArrow, [.command]),
        (rightArrow, [.command]),
    ]

    static let textEditingKeys: Set<String> = Set(
        [
            NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSUpArrowFunctionKey, NSDownArrowFunctionKey,
            NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey, NSDeleteFunctionKey,
        ]
            .compactMap { UnicodeScalar($0).map(String.init) } + ["\u{7f}"]
    )

    static func textEditorAnswersFirst(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags.contains(.command), flags.isSubset(of: [.command, .option, .shift]) else { return false }
        return textEditingKeys.contains(event.charactersIgnoringModifiers ?? "")
    }

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
    private let fallbackCoordinator: AppCoordinator?
    private weak var application: BrowserApplication?
    private var coordinator: AppCoordinator {
        if let application {
            return application.ensureActiveWindow()
        }
        guard let fallbackCoordinator else { preconditionFailure("Menu has no application") }
        return fallbackCoordinator
    }

    init(coordinator: AppCoordinator) {
        fallbackCoordinator = coordinator
        super.init()
    }

    init(application: BrowserApplication) {
        fallbackCoordinator = nil
        self.application = application
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

        // A rebuilt menu must also include browser windows that are already open.
        let coordinators = application?.windows ?? fallbackCoordinator.map { [$0] } ?? []
        for coordinator in coordinators {
            guard let nativeWindow = coordinator.nativeWindow,
                  !nativeWindow.isExcludedFromWindowsMenu else { continue }
            NSApp.addWindowsItem(nativeWindow, title: nativeWindow.title, filename: false)
        }
    }

    // MARK: - Menus

    private func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(chain("About Linen", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(command("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(command("Release Notes…", #selector(showReleaseNotes)))
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
        menu.addItem(command("New Window", #selector(newWindow), key: "n"))
        menu.addItem(command("New Private Window", #selector(newPrivateWindow), key: "n", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(command("Reopen Last Closed Tab", #selector(reopenClosedTab), key: "t", modifiers: [.command, .shift]))
        menu.addItem(command("Reopen Last Closed Window", #selector(reopenClosedWindow)))
        menu.addItem(.separator())
        menu.addItem(command("Close Tab", #selector(closeTab), key: "w"))
        menu.addItem(chain(
            "Close Window",
            #selector(NSWindow.performClose(_:)),
            key: "w",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(command("Pin This Page", #selector(pinPage), key: "d"))
        menu.addItem(command(
            "Back to Pinned Page",
            #selector(returnToPin),
            key: "d",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(command("Open Location…", #selector(openLocation), key: "l"))
        menu.addItem(command("Search Everything…", #selector(openPalette), key: "k"))
        menu.addItem(.separator())
        menu.addItem(command("Downloads", #selector(openDownloads), key: "l", modifiers: [.command, .option]))
        menu.addItem(.separator())
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
        menu.addItem(command("Show Reader", #selector(toggleReader), key: "r", modifiers: [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(chain(
            "Enter Full Screen",
            #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.command, .control]
        ))
        menu.addItem(.separator())
        menu.addItem(submenu(splitViewMenu(), titled: "Split View"))
        menu.addItem(.separator())
        menu.addItem(command("Hide Sidebar", #selector(toggleSidebar), key: "s", modifiers: [.command, .control]))
        menu.addItem(command(
            "Show Side Panel",
            #selector(toggleSidePanel),
            key: "s",
            modifiers: [.command, .option]
        ))
        menu.addItem(.separator())
        let developer = NSMenu()
        developer.addItem(command(
            "Show Web Inspector",
            #selector(showWebInspector),
            key: "i",
            modifiers: [.command, .option]
        ))
        developer.addItem(command("Restart Page", #selector(restartPage)))
        menu.addItem(submenu(developer, titled: "Developer"))
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
        (application?.ensureActiveWindow() ?? coordinator).openSettings()
    }

    @objc private func checkForUpdates() {
        (application?.updates ?? coordinator.updates).checkNow()
    }
    @objc private func showReleaseNotes() {
        coordinator.showReleaseNotes()
    }

    @objc private func openDownloads() {
        coordinator.openSettings(.downloads)
    }
    @objc private func newTab() {
        (application?.ensureActiveWindow() ?? coordinator).requestNewTab()
    }
    @objc private func newWindow() {
        if let coordinator = application?.activeCoordinator ?? fallbackCoordinator {
            coordinator.requestNewWindow()
        } else {
            application?.newWindow(profile: ProfileStore.shared.current)
        }
    }
    @objc private func reopenClosedWindow() {
        application?.reopenLastClosedWindow()
    }
    @objc private func newPrivateWindow() {
        if let coordinator = application?.activeCoordinator ?? fallbackCoordinator {
            coordinator.requestNewWindow(isPrivate: true)
        } else {
            application?.newWindow(
                profile: .privateBrowsing(),
                settingsOwner: ProfileStore.shared.current
            )
        }
    }
    @objc private func closeTab() {
        coordinator.closeActiveTabAskingIfPinned()
    }
    @objc private func reopenClosedTab() {
        if application?.activeCoordinator == nil {
            application?.reopenLastClosedWindow()
        } else {
            coordinator.browser.reopenLastClosedTab()
        }
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
        coordinator.pageCommandTab?.reload()
    }
    @objc private func hardReload() {
        activeWebView?.reloadFromOrigin()
    }
    @objc private func showWebInspector() {
        coordinator.pageCommandTab?.showWebInspector()
    }

    @objc private func restartPage() {
        coordinator.pageCommandTab?.restartPage()
    }
    @objc private func stopLoading() {
        coordinator.pageCommandTab?.stopLoading()
    }
    @objc private func goBack() {
        coordinator.pageCommandTab?.goBack()
    }
    @objc private func goForward() {
        coordinator.pageCommandTab?.goForward()
    }
    @objc private func toggleSidebar() {
        coordinator.toggleSidebar()
    }
    @objc private func toggleSidePanel() {
        coordinator.toggleSidePanel()
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

    @objc private func toggleReader() {
        coordinator.toggleReader()
    }

    @objc private func openFind() {
        coordinator.pageCommandTab?.find.open()
    }
    @objc private func findNext() {
        coordinator.pageCommandTab?.find.findNext(backwards: false)
    }
    @objc private func findPrevious() {
        coordinator.pageCommandTab?.find.findNext(backwards: true)
    }

    @objc private func nextTab() {
        coordinator.browser.cycleTab(forward: true)
    }
    @objc private func previousTab() {
        coordinator.browser.cycleTab(forward: false)
    }
    @objc private func switchToNextTab() {
        switchTab(forward: true)
    }
    @objc private func switchToPreviousTab() {
        switchTab(forward: false)
    }
    private func switchTab(forward: Bool) {
        coordinator.shiftStep.cancel()
        coordinator.browser.switchTab(forward: forward)
        if !NSEvent.modifierFlags.contains(.control) {
            coordinator.browser.endTabSwitching()
        }
    }
    @objc private func showTabAtIndex(_ sender: NSMenuItem) {
        coordinator.browser.activateTab(at: sender.tag)
    }
    @objc private func showLastTab() {
        coordinator.browser.activateLastTab()
    }

    @objc private func clearHistory() {
        coordinator.confirmClearHistory()
    }

    @objc private func printPage() {
        coordinator.printActivePage()
    }

    @objc private func actualSize() {
        coordinator.pageCommandTab?.resetZoom()
    }
    @objc private func zoomIn() {
        coordinator.pageCommandTab?.zoomIn()
    }
    @objc private func zoomOut() {
        coordinator.pageCommandTab?.zoomOut()
    }

    private var activeWebView: WKWebView? {
        coordinator.pageCommandTab?.webView
    }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {  // swiftlint:disable:this cyclomatic_complexity
        if menuItem.action == #selector(reopenClosedWindow) {
            return application?.canReopenWindow == true
        }
        if let application, application.activeCoordinator == nil {
            return [#selector(newWindow), #selector(newTab), #selector(newPrivateWindow),
                    #selector(openSettings), #selector(checkForUpdates), #selector(reopenClosedTab),
            ]
                .contains(menuItem.action)
        }
        switch menuItem.action {
        case #selector(goBack):
            return coordinator.pageCommandTab?.canGoBack ?? false
        case #selector(goForward):
            return coordinator.pageCommandTab?.canGoForward ?? false
        case #selector(actualSize):
            return coordinator.pageCommandTab?.isZoomed ?? false
        case #selector(copyPageURL):
            guard let tab = coordinator.pageCommandTab else { return false }
            return coordinator.linkURL(for: tab) != nil
        case #selector(showWebInspector):
            return coordinator.pageCommandTab != nil && coordinator.settings.webInspectorEnabled
        case #selector(restartPage):
            guard let tab = coordinator.pageCommandTab else { return false }
            return tab.extensionBaseURL == nil
        case #selector(reload), #selector(hardReload),
             #selector(zoomIn), #selector(zoomOut), #selector(openFind), #selector(findNext),
             #selector(findPrevious), #selector(printPage):
            return coordinator.pageCommandTab != nil
        case #selector(closeTab):
            return coordinator.browser.activeTab != nil
        case #selector(stopLoading):
            return coordinator.pageCommandTab?.isLoading ?? false
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
        case #selector(nextTab), #selector(previousTab), #selector(showLastTab),
             #selector(switchToNextTab), #selector(switchToPreviousTab):
            return coordinator.browser.tabs.count > 1
        case #selector(showTabAtIndex(_:)):
            return coordinator.browser.tabs.indices.contains(menuItem.tag)
        case #selector(clearHistory):
            return coordinator.browser.history.count > 0
        case #selector(checkForUpdates):
            return coordinator.updates.canCheck
        case #selector(toggleSidebar):
            let sidebarTitle: LocalizedStringResource = coordinator.sidebar.isVisible
                ? "Hide Sidebar" : "Show Sidebar"
            menuItem.title = String(localized: sidebarTitle)
            return true
        case #selector(toggleReader):
            let readerTitle: LocalizedStringResource = coordinator.readerTab?.reader.isActive == true
                ? "Hide Reader"
                : "Show Reader"
            menuItem.title = String(localized: readerTitle)
            return coordinator.readerTab?.reader.isAvailable ?? false
        case #selector(toggleSidePanel):
            let sidePanelTitle: LocalizedStringResource = coordinator.sidePanel.isVisible
                ? "Hide Side Panel"
                : "Show Side Panel"
            menuItem.title = String(localized: sidePanelTitle)
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
