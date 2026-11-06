// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

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

        let help = helpMenu()
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

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(command("Report a Problem…", #selector(reportProblem)))
        menu.addItem(command("Linen on GitHub…", #selector(openGitHubRepository)))
        return menu
    }

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
        menu.addItem(submenu(services, titled: "Services", symbol: "gearshape.2"))
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
        menu.addItem(command("Reopen Closed Tab", #selector(reopenClosedTab), key: "t", modifiers: [.command, .shift]))
        menu.addItem(command("Reopen Closed Window", #selector(reopenClosedWindow)))
        menu.addItem(.separator())
        menu.addItem(command("Close Tab", #selector(closeTab), key: "w"))
        menu.addItem(chain(
            "Close Window",
            #selector(NSWindow.performClose(_:)),
            key: "w",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(command("Duplicate Tab", #selector(duplicateTab), key: "d", modifiers: [.command, .shift]))
        menu.addItem(command("Pin Tab", #selector(pinPage), key: "d"))
        menu.addItem(command(
            "Back to Pin",
            #selector(returnToPin),
            key: "h",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(command("Open Location…", #selector(openLocation), key: "l"))
        menu.addItem(command("Search Everything…", #selector(openPalette), key: "k"))
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
        menu.addItem(command(
            "Search with \(SearchURLBuilder.engine.name)",
            #selector(searchSelection),
            key: "l",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(command("Find…", #selector(openFind), key: "f"))
        find.addItem(command("Find Next", #selector(findNext), key: "g"))
        find.addItem(command("Find Previous", #selector(findPrevious), key: "g", modifiers: [.command, .shift]))
        menu.addItem(submenu(find, titled: "Find", symbol: "text.magnifyingglass"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(command("Hide Sidebar", #selector(toggleSidebar), key: "s", modifiers: [.command, .control]))
        menu.addItem(command(
            "Show Side Panel",
            #selector(toggleSidePanel),
            key: "s",
            modifiers: [.command, .option]
        ))
        menu.addItem(command("Show Downloads", #selector(openDownloads), key: "l", modifiers: [.command, .option]))
        menu.addItem(.separator())
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
        menu.addItem(command("Translate Page", #selector(toggleTranslation)))
        menu.addItem(.separator())
        menu.addItem(submenu(splitViewMenu(), titled: "Split View", symbol: "rectangle.split.2x1"))
        menu.addItem(.separator())
        menu.addItem(command(
            "Use Minimal Window Style",
            #selector(toggleMinimal),
            key: "m",
            modifiers: [.command, .shift]
        ))
        menu.addItem(command("Move Bar to Top", #selector(moveMinimalBar)))
        menu.addItem(.separator())
        menu.addItem(chain(
            "Enter Full Screen",
            #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.command, .control]
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
        developer.addItem(.separator())
        developer.addItem(command("Developer Mode", #selector(toggleDeveloperMode)))
        menu.addItem(submenu(developer, titled: "Developer", symbol: "hammer"))
        return menu
    }

    private func splitViewMenu() -> NSMenu {
        let menu = NSMenu()
        let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let downArrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        menu.addItem(command("Split Right", #selector(splitRight), key: rightArrow, modifiers: [.command, .control]))
        menu.addItem(command("Split Down", #selector(splitDown), key: downArrow, modifiers: [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(command("Show Other Pane", #selector(focusOtherPane), key: "]", modifiers: [.command, .option]))
        menu.addItem(command("Swap Panes", #selector(swapPanes)))
        menu.addItem(command("Stack Panes", #selector(toggleSplitAxis)))
        menu.addItem(.separator())
        menu.addItem(command("Exit Split View", #selector(exitSplit)))
        menu.addItem(command("Close Other Panes", #selector(closeOtherPanes)))
        return menu
    }

    private func historyMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(command("Back", #selector(goBack), key: "["))
        menu.addItem(command("Forward", #selector(goForward), key: "]"))
        menu.addItem(hidden(command("Back", #selector(goBack), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!))))
        menu.addItem(hidden(command("Forward", #selector(goForward), key: String(UnicodeScalar(NSRightArrowFunctionKey)!))))
        menu.addItem(.separator())
        menu.addItem(command("Show History", #selector(showHistory), key: "y"))
        menu.addItem(command("Clear History…", #selector(clearHistory)))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(chain("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(chain("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(command("Next Tab", #selector(nextTab), key: "]", modifiers: [.command, .shift]))
        menu.addItem(command("Previous Tab", #selector(previousTab), key: "[", modifiers: [.command, .shift]))
        menu.addItem(hidden(command("Next Tab", #selector(switchToNextTab), key: "\t", modifiers: [.control])))
        menu.addItem(hidden(command(
            "Previous Tab",
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
        for slot in SpaceShortcut.slots {
            menu.addItem(hidden(command("Show Space \(slot)", #selector(showSpaceAtIndex(_:)), key: "\(slot)", modifiers: SpaceShortcut.modifiers)))
            menu.items.last?.tag = slot - 1
        }
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
    @objc private func reportProblem() {
        openHelpLink("https://github.com/kavoye/linen-browser/issues/new?template=bug_report.yml")
    }
    @objc private func openGitHubRepository() {
        openHelpLink("https://github.com/kavoye/linen-browser")
    }
    private func openHelpLink(_ address: String) {
        guard let url = URL(string: address) else { return }
        coordinator.openInBrowser(url)
    }

    @objc private func openDownloads() {
        coordinator.showDownloads()
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
    @objc private func searchSelection() {
        (activeWebView as? TabWebView)?.searchSelection()
    }

    @objc private func duplicateTab() {
        guard let tab = coordinator.browser.activeTab else { return }
        coordinator.browser.duplicate(tab)
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
    @objc private func toggleDeveloperMode() {
        guard let tab = coordinator.pageCommandTab else { return }
        tab.setDeveloperMode(!tab.usesDeveloperMode)
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
    @objc private func toggleMinimal() {
        coordinator.toggleMinimal()
    }
    @objc private func moveMinimalBar() {
        coordinator.moveMinimalBar()
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
    @objc private func showSpaceAtIndex(_ sender: NSMenuItem) {
        let spaces = coordinator.spaceStore.spaces
        guard spaces.indices.contains(sender.tag) else { return }
        coordinator.switchSpace(to: spaces[sender.tag])
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
    @objc private func toggleTranslation() {
        guard let tab = coordinator.pageCommandTab else { return }
        coordinator.toggleTranslation(tab)
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
                    #selector(reportProblem), #selector(openGitHubRepository),
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
        case #selector(searchSelection):
            guard let tab = coordinator.pageCommandTab else { return false }
            menuItem.title = String(localized: "Search with \(SearchURLBuilder.engine(settings: tab.context.settings).name)")
            return true
        case #selector(showWebInspector):
            guard let tab = coordinator.pageCommandTab else { return false }
            return coordinator.settings.webInspectorEnabled || tab.usesDeveloperMode
        case #selector(restartPage):
            guard let tab = coordinator.pageCommandTab else { return false }
            return tab.extensionBaseURL == nil
        case #selector(toggleDeveloperMode):
            guard let tab = coordinator.pageCommandTab,
                  let host = DeveloperMode.host(of: URL(string: tab.urlString))
            else {
                menuItem.title = String(localized: "Developer Mode")
                menuItem.state = .off
                return false
            }
            menuItem.title = String(localized: "Developer Mode for “\(host)”")
            menuItem.state = tab.usesDeveloperMode ? .on : .off
            return true
        case #selector(reload), #selector(hardReload):
            return coordinator.pageCommandTab?.canReload ?? false
        case #selector(zoomIn), #selector(zoomOut), #selector(openFind), #selector(findNext),
             #selector(findPrevious), #selector(printPage):
            return coordinator.pageCommandTab != nil
        case #selector(closeTab), #selector(duplicateTab):
            return coordinator.browser.activeTab != nil
        case #selector(pinPage):
            return validatePinItem(menuItem)
        case #selector(returnToPin):
            return coordinator.browser.activeTab?.isAwayFromPin ?? false
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
        case #selector(toggleTranslation):
            let translationTitle: LocalizedStringResource = coordinator.pageCommandTab?.translation.isActive == true
                ? "View Original"
                : "Translate Page"
            menuItem.title = String(localized: translationTitle)
            return coordinator.pageCommandTab?.canToggleTranslation ?? false
        case #selector(toggleSplitAxis):
            let axisTitle: LocalizedStringResource = coordinator.browser.activeSplit?.axis == .stacked
                ? "Place Side by Side"
                : "Stack Panes"
            menuItem.title = String(localized: axisTitle)
            return coordinator.browser.activeSplit?.axis != nil
        case #selector(reopenClosedTab):
            return coordinator.browser.canReopenClosedTab
        case #selector(nextTab), #selector(previousTab), #selector(showLastTab),
             #selector(switchToNextTab), #selector(switchToPreviousTab):
            return coordinator.browser.currentSpaceTabs.count > 1
        case #selector(showTabAtIndex(_:)):
            return coordinator.browser.currentSpaceTabs.indices.contains(menuItem.tag)
        case #selector(showSpaceAtIndex(_:)):
            return coordinator.showsSpaces && coordinator.spaceStore.spaces.indices.contains(menuItem.tag)
        case #selector(clearHistory):
            return coordinator.browser.history.count > 0
        case #selector(checkForUpdates):
            return coordinator.updates.canCheck
        case #selector(toggleSidebar):
            let sidebarTitle: LocalizedStringResource = coordinator.sidebar.isVisible
                ? "Hide Sidebar" : "Show Sidebar"
            menuItem.title = String(localized: sidebarTitle)
            return !coordinator.settings.isMinimal
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
        case #selector(toggleMinimal):
            let windowStyleTitle: LocalizedStringResource = coordinator.settings.isMinimal
                ? "Use Standard Window Style"
                : "Use Minimal Window Style"
            menuItem.title = String(localized: windowStyleTitle)
            return true
        case #selector(moveMinimalBar):
            return validateMoveBarItem(menuItem)
        default:
            return true
        }
    }

    private func validatePinItem(_ item: NSMenuItem) -> Bool {
        let isShowingPin = coordinator.browser.activeTab?.isShowingPin == true
        let title: LocalizedStringResource = isShowingPin ? "Unpin Tab" : "Pin Tab"
        item.title = String(localized: title)
        item.image = NSImage(systemSymbolName: isShowingPin ? "pin.slash" : "pin", accessibilityDescription: nil)
        return coordinator.browser.activeTab != nil
    }

    private func validateMoveBarItem(_ item: NSMenuItem) -> Bool {
        let barIsAtTop = coordinator.settings.minimalBarEdge == .top
        let title: LocalizedStringResource = barIsAtTop ? "Move Bar to Bottom" : "Move Bar to Top"
        item.title = String(localized: title)
        item.image = NSImage(
            systemSymbolName: barIsAtTop ? "rectangle.bottomthird.inset.filled" : "rectangle.topthird.inset.filled",
            accessibilityDescription: nil
        )
        return coordinator.settings.isMinimal
    }

    // MARK: - Building blocks

    private func submenu(
        _ menu: NSMenu,
        titled title: LocalizedStringResource,
        symbol: String? = nil
    ) -> NSMenuItem {
        let name = String(localized: title)
        let holder = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        menu.title = name
        holder.submenu = menu
        holder.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
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

    private static let symbols: [Selector: String] = [
        #selector(NSApplication.orderFrontStandardAboutPanel(_:)): "info",
        #selector(checkForUpdates): "arrow.triangle.2.circlepath",
        #selector(showReleaseNotes): "doc.text",
        #selector(reportProblem): "exclamationmark.bubble",
        #selector(openGitHubRepository): "chevron.left.forwardslash.chevron.right",
        #selector(openSettings): "gearshape",
        #selector(NSApplication.hide(_:)): "eye.slash",
        #selector(NSApplication.hideOtherApplications(_:)): "rectangle.on.rectangle.slash",
        #selector(NSApplication.unhideAllApplications(_:)): "eye",
        #selector(NSApplication.terminate(_:)): "power",
        #selector(newTab): "plus.square",
        #selector(newWindow): "macwindow.badge.plus",
        #selector(newPrivateWindow): "hand.raised",
        #selector(reopenClosedTab): "arrow.uturn.backward.square",
        #selector(reopenClosedWindow): "macwindow",
        #selector(closeTab): "xmark",
        #selector(NSWindow.performClose(_:)): "xmark.square",
        #selector(duplicateTab): "plus.square.on.square",
        #selector(pinPage): "pin",
        #selector(returnToPin): "arrow.uturn.backward",
        #selector(openLocation): "globe",
        #selector(openPalette): "magnifyingglass",
        #selector(openDownloads): "arrow.down",
        #selector(printPage): "printer",
        Selector(("undo:")): "arrow.uturn.backward",
        Selector(("redo:")): "arrow.uturn.forward",
        #selector(NSText.cut(_:)): "scissors",
        #selector(NSText.copy(_:)): "doc.on.doc",
        #selector(NSText.paste(_:)): "doc.on.clipboard",
        #selector(NSTextView.pasteAsPlainText(_:)): "textformat",
        #selector(NSText.delete(_:)): "trash",
        #selector(NSText.selectAll(_:)): "selection.pin.in.out",
        #selector(copyPageURL): "link",
        #selector(searchSelection): "character.magnify",
        #selector(openFind): "text.magnifyingglass",
        #selector(findNext): "chevron.down",
        #selector(findPrevious): "chevron.up",
        #selector(reload): "arrow.clockwise",
        #selector(hardReload): "arrow.2.circlepath",
        #selector(stopLoading): "stop",
        #selector(actualSize): "1.magnifyingglass",
        #selector(zoomIn): "plus.magnifyingglass",
        #selector(zoomOut): "minus.magnifyingglass",
        #selector(toggleReader): "doc.plaintext",
        #selector(toggleTranslation): "translate",
        #selector(NSWindow.toggleFullScreen(_:)): "arrow.up.left.and.arrow.down.right.rectangle",
        #selector(toggleSidebar): "sidebar.left",
        #selector(toggleSidePanel): "sidebar.right",
        #selector(toggleMinimal): "rectangle.compress.vertical",
        #selector(moveMinimalBar): "rectangle.topthird.inset.filled",
        #selector(showWebInspector): "wrench.and.screwdriver",
        #selector(restartPage): "arrow.trianglehead.2.clockwise",
        #selector(toggleDeveloperMode): "hammer",
        #selector(splitRight): "rectangle.split.2x1",
        #selector(splitDown): "rectangle.split.1x2",
        #selector(focusOtherPane): "rectangle.lefthalf.inset.filled",
        #selector(swapPanes): "arrow.left.arrow.right",
        #selector(toggleSplitAxis): "rectangle.landscape.rotate",
        #selector(exitSplit): "rectangle",
        #selector(closeOtherPanes): "xmark.square",
        #selector(goBack): "chevron.left",
        #selector(goForward): "chevron.right",
        #selector(showHistory): "clock",
        #selector(clearHistory): "clock.badge.xmark",
        #selector(NSWindow.performMiniaturize(_:)): "minus.square",
        #selector(NSWindow.performZoom(_:)): "square.arrowtriangle.4.outward",
        #selector(nextTab): "chevron.right.square",
        #selector(previousTab): "chevron.left.square",
        #selector(NSApplication.arrangeInFront(_:)): "macwindow.on.rectangle",
    ]

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
        item.image = Self.symbols[action].flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return item
    }

    private func hidden(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.isAlternate = false
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }
}
