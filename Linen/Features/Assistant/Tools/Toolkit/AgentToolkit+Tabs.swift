// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func navigate(to rawURL: String) async -> String {
        let destination = normalized(rawURL)
        let step = beginTool(name: "navigate")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let url = destination else {
            let output = "Invalid URL."
            completeTool(step, failed: true)
            return output
        }
        if let output = outboundDenial(for: url) {
            completeTool(step, failed: true)
            return output
        }

        guard let tab = visibleTaskTab else {
            let output = String(localized: "The active tab changed before the assistant could use it.")
            completeTool(step, failed: true)
            return output
        }
        let webView = tab.webView
        guard let navigation = tab.load(url, transition: .agent) else {
            let output = "Couldn’t open the page in the active tab."
            completeTool(step, failed: true)
            return output
        }
        let loaded = await waitForVisibleNavigation(navigation, in: tab)
        if let cancelled = cancellationOutput(for: step) {
            tab.stopLoading()
            return cancelled
        }
        guard loaded else {
            let output = "Couldn’t open the page in the active tab."
            completeTool(step, failed: true)
            return output
        }
        let access = await authorize(.read, in: webView)
        if let denial = access.denial {
            completeTool(step, failed: true)
            return denial
        }
        let output = await guardedPageOperation(in: webView, authorization: access.authorization, capability: .read) {
            await PageDriver.readRenderedPage(
                webView,
                maxTextLength: outputBudget.pageTextCharacters,
                controlLimit: outputBudget.controlLimit
            )
        }
        if let cancelled = cancellationOutput(for: step) {
            tab.stopLoading()
            return cancelled
        }
        if let denial = postflightDenial(for: access.authorization, in: webView) {
            completeTool(step, failed: true)
            return denial
        }
        let links = links(in: output)
        remember(links: links)
        completeTool(step, failed: !output.hasPrefix("PAGE TEXT:"))
        return fencedPageOutput("pageID: \(tab.id.uuidString)\n" + output)
    }

    func newTab(url rawURL: String?) async -> String {
        let step = beginTool(name: "newTab")
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let rawURL, !rawURL.isEmpty {
            guard let url = normalized(rawURL) else {
                let output = "Invalid URL."
                completeTool(step, failed: true)
                return output
            }
            if let output = outboundDenial(for: url) {
                completeTool(step, failed: true)
                return output
            }
            let tab = browser.newTab(url: url, transition: .agent)
            adoptOpened(tab)
            await PageSettle.untilFirstRender(of: tab)
            tab.assistantAccess.pageChanged(url: url)
            let access = await authorize(.read, in: tab.webView, requiresTaskTab: false)
            if let output = cancellationOutput(for: step) {
                browser.close(tab, recordForReopening: false)
                return output
            }
            if let output = access.denial {
                completeTool(step, failed: true)
                return output
            }
            let output = await PageDriver.readRenderedPage(
                tab.webView,
                maxTextLength: outputBudget.pageTextCharacters,
                controlLimit: outputBudget.controlLimit
            )
            if let cancelled = cancellationOutput(for: step) {
                browser.close(tab, recordForReopening: false)
                return cancelled
            }
            if let output = postflightDenial(for: access.authorization, in: tab.webView) {
                completeTool(step, failed: true)
                return output
            }
            let pageLinks = links(in: output)
            remember(links: pageLinks)
            let openedLink = ConversationLog.ActivityLink(
                title: url.host() ?? url.absoluteString,
                url: url
            )
            remember(links: [openedLink])
            completeTool(step)
            return fencedPageOutput(output)
        }
        let tab = browser.newTab()
        adoptOpened(tab)
        let output = "New empty tab opened and active."
        completeTool(step)
        return output
    }

    func switchTab(matching reference: String) -> String {
        let step = beginTool(name: "switchTab")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard let tab = scope.contextTab(matching: reference) else {
            let output = scope.missingContextTabOutput()
            completeTool(step, failed: true)
            return output
        }
        browser.activate(tab)
        browser.onTabAlert?(.agentSwitched(tab))
        let output = "Switched to “\(tab.title)”."
        completeTool(step)
        return output
    }

    func closeTab(matching reference: String?) -> String {
        let step = beginTool(name: "closeTab")
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let reference, !reference.isEmpty {
            guard let tab = scope.contextTab(matching: reference) else {
                let output = "No tab in this conversation matches that."
                completeTool(step, failed: true)
                return output
            }
            browser.close(tab)
            browser.onTabAlert?(.agentClosed(tab.title))
            let output = "Closed “\(tab.title)”."
            completeTool(step)
            return output
        }
        guard let active = browser.activeTab else {
            let output = "There are no tabs open."
            completeTool(step, failed: true)
            return output
        }
        guard scope.contextTabIDs.contains(active.id) else {
            let output = String(localized: "The active tab changed before the assistant could use it.")
            completeTool(step, failed: true)
            return output
        }
        browser.close(active)
        browser.onTabAlert?(.agentClosed(active.title))
        let output = "Closed the active tab."
        completeTool(step)
        return output
    }

    func listTabs() -> String {
        let step = beginTool(name: "listTabs")
        if let output = cancellationOutput(for: step) {
            return output
        }
        let readable = scope.contextTabIDs
        let tabs = browser.tabs.filter { $0.assistantAccess.effectivePolicy != .deny }
        guard !tabs.isEmpty else {
            let output = "No tabs are open."
            completeTool(step)
            return output
        }
        let lines = tabs.enumerated().map { index, tab -> String in
            let place = URL(string: tab.urlString)?.displayHost
                ?? tab.internalPage?.title
                ?? "blank"
            let active = tab.id == browser.activeTabID ? " ← ACTIVE" : ""
            let reach = readable.contains(tab.id) ? "" : " — title only"
            return "\(index + 1). [\(tab.id.uuidString)] \(tab.title) (\(place))\(active)\(reach)"
        }
        let note = tabs.contains { !readable.contains($0.id) }
            ? "\nOnly the tabs without “title only” can be read. To read one of the others, "
                + "switch to it, or ask the person to attach it with @."
            : ""
        let output = "\(tabs.count) tabs open:\n" + lines.joined(separator: "\n") + note
        completeTool(step)
        return output
    }

    func adoptOpened(_ tab: BrowserTab) {
        scope.noteOpened(tab)
        browser.onTabAlert?(.agentOpened(tab))
        guard let task = scope.task else { return }
        let anchor = browser.anchorID(of: tab.id)
        log.noteOpenedTab(anchor, taskID: task.id)
        browser.setAgentWorking(true, inAnchor: anchor)
    }

    func normalized(_ rawURL: String) -> URL? {
        if let url = URL(string: rawURL), let scheme = url.scheme,
           scheme == "https" || scheme == "http" {
            return url
        }
        if !rawURL.contains(" "), rawURL.contains(".") {
            return URL(string: "https://\(rawURL)")
        }
        return nil
    }

    private func waitForVisibleNavigation(_ navigation: WKNavigation, in tab: BrowserTab) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if tab.committedNavigation === navigation {
                return await PageSettle.untilIdle(tab.webView, timeout: .seconds(15)) && !tab.isShowingError
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
