// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import MCP
import Observation
import WebKit

@MainActor
@Observable
final class MCPBrowserSession: Identifiable {
    struct Grant {
        let origin: String
        let access: MCPAccessConsent.Access
    }

    struct PageObservation {
        let id: String
        let snapshot: String
        let documentURL: String
    }

    let id = UUID()
    var clientName = String(localized: "External Connection")
    private(set) var isConnected = true
    private(set) var lastTool = ""
    private(set) var completedCalls = 0
    private(set) var grants: [UUID: Grant] = [:]
    @ObservationIgnored private let browser: BrowserModel
    @ObservationIgnored private let available: () -> Bool
    @ObservationIgnored private let consent: (String, [MCPAccessConsent.Page]) async -> MCPAccessConsent.Access?
    @ObservationIgnored private let openConsent: (String, URL) async -> Bool
    @ObservationIgnored private let actionPolicy = AgentActionPolicy(storage: MCPActionGrantStorage())
    @ObservationIgnored private var observations: [UUID: PageObservation] = [:]
    @ObservationIgnored private var destinations: Set<String> = []
    @ObservationIgnored private var hasReadContent = false
    @ObservationIgnored private var accessWasRequested = false
    @ObservationIgnored private var busy = false

    var lastActionTitle: String? {
        guard !lastTool.isEmpty else { return nil }
        if let descriptor = AgentToolCatalog.all.first(where: { $0.id == lastTool }) {
            return String(localized: descriptor.title)
        }
        return String(localized: "Request Tab Access")
    }

    init(
        browser: BrowserModel,
        available: @escaping () -> Bool,
        consent: @escaping (String, [MCPAccessConsent.Page]) async -> MCPAccessConsent.Access? = MCPAccessConsent.share,
        openConsent: @escaping (String, URL) async -> Bool = MCPAccessConsent.open
    ) {
        self.browser = browser
        self.available = available
        self.consent = consent
        self.openConsent = openConsent
    }

    func revoke() {
        isConnected = false
        grants = [:]
        observations = [:]
        destinations = []
        actionPolicy.revokeAll()
    }

    func call(name: String, arguments: [String: Value]) async throws -> CallTool.Result {
        guard let entry = MCPToolCatalog.entries.first(where: { $0.name == name }) else {
            throw MCPError.invalidParams("Unknown tool.")
        }
        try entry.validate(arguments)
        guard isConnected, available(), !Task.isCancelled else {
            return failure("Connection is unavailable. Reconnect after leaving private browsing or after the assistant finishes.")
        }
        guard !busy else { return failure("Another operation is running. Wait for its result.") }
        busy = true
        lastTool = name
        defer {
            busy = false
            completedCalls += 1
        }
        return await AgentActionConsent.$scopedPolicy.withValue(actionPolicy) {
            await AgentActionConsent.$externalClientName.withValue(clientName) {
                await execute(name: name, arguments: arguments)
            }
        }
    }

    private func execute(name: String, arguments: [String: Value]) async -> CallTool.Result {
        switch name {
        case "requestAccess":
            return await requestAccess()
        case "listTabs":
            return tabList()
        case "newTab":
            return await openNewTab(arguments["url"]?.stringValue ?? "")
        default:
            break
        }
        guard let id = arguments["tabID"]?.stringValue.flatMap(UUID.init(uuidString:)),
            let tab = sharedTab(id), let grant = grants[id]
        else { return failure("This tab is not shared with this connection.") }
        let capability: AssistantPageCapability = ["readPage", "inspectControl", "waitForPage", "screenshotPage"].contains(name) ? .read : .control
        guard permits(tab, capability: capability) else {
            return failure("This action is blocked by the connection’s access or the website’s Assistant Access setting.")
        }
        if name == "switchTab" {
            browser.activate(tab)
            return success("Tab activated. Use readPage for fresh controls.")
        }
        if name == "closeTab" {
            guard tab.pinnedURL == nil else { return failure("Pinned tabs must be closed by the user.") }
            browser.close(tab)
            grants[id] = nil
            observations[id] = nil
            return success("Tab closed.")
        }
        if capability == .control, !onScreen(tab) {
            return failure("Use switchTab before controlling this shared tab.")
        }
        if name == "navigate" {
            return await navigate(arguments["url"]?.stringValue ?? "", tab: tab, grant: grant)
        }
        if name == "goBack" {
            guard let destination = tab.webView.backForwardList.backItem?.url else {
                return failure("There is no page to go back to.")
            }
            guard SitePermissions.origin(for: destination) == grant.origin else {
                return failure("The previous page belongs to another website. Ask the user to open and share it.")
            }
        }
        return await usePage(name: name, arguments: arguments, tab: tab, capability: capability)
    }

    private func requestAccess() async -> CallTool.Result {
        guard !accessWasRequested else {
            return failure("Access has already been requested. The user can disconnect and reconnect to share different tabs.")
        }
        let tabs = browser.splitPanes ?? browser.activeTab.map { [$0] } ?? []
        let pages = tabs.compactMap { tab -> MCPAccessConsent.Page? in
            guard !tab.isPrivate, let url = webURL(of: tab), tab.assistantAccess.effectivePolicy != .deny else { return nil }
            return .init(id: tab.id, title: tab.title, url: url)
        }
        guard !pages.isEmpty else {
            _ = await consent(clientName, [])
            return failure("No shareable webpage is on screen. Linen showed the user how to open a webpage. Request access again after they have opened it.")
        }
        accessWasRequested = true
        let answer = await consent(clientName, pages)
        guard isConnected, available(), !Task.isCancelled, let answer else { return failure("Access was not granted.") }
        for page in pages {
            guard let tab = browser.tabs.first(where: { $0.id == page.id }),
                !tab.isPrivate, webURL(of: tab) == page.url,
                tab.assistantAccess.effectivePolicy != .deny
            else { continue }
            grants[page.id] = Grant(origin: SitePermissions.origin(for: page.url), access: answer)
        }
        return tabList()
    }

    private func tabList() -> CallTool.Result {
        let tabs: [Value] = browser.tabs.compactMap { tab in
            guard sharedTab(tab.id) != nil else { return nil }
            return .object([
                "tabID": .string(tab.id.uuidString), "title": .string(tab.title),
                "url": .string(webURL(of: tab)?.absoluteString ?? ""),
                "active": .bool(browser.activeTabID == tab.id),
                "canControl": .bool(permits(tab, capability: .control)),
            ])
        }
        let content: Value = .object(["tabs": .array(tabs)])
        return CallTool.Result(
            content: [.text(text: encoded(content), annotations: nil, _meta: nil)], structuredContent: Optional.some(content), isError: false)
    }

    private func usePage(
        name: String, arguments: [String: Value], tab: BrowserTab, capability: AssistantPageCapability
    ) async -> CallTool.Result {
        tab.setExternalAutomationWorking(true)
        defer { tab.setExternalAutomationWorking(false) }
        tab.realizeDeferredSession()
        let view = tab.webView
        guard let url = webURL(of: tab) else { return failure("The webpage is unavailable.") }
        let usesRef =
            ["clickOnPage", "typeOnPage", "selectOption", "fillFields", "inspectControl", "setChecked", "hoverOnPage", "pressKey"].contains(name)
            || arguments["ref"] != nil
        let observation = observations[tab.id]
        if usesRef {
            guard let observation, observation.id == arguments["observationID"]?.stringValue,
                observation.documentURL == url.absoluteString
            else { return failure("The observation is stale. Use readPage again.") }
        }
        let scope = PageAutomationGuard(
            documentURL: url.absoluteString, snapshot: usesRef ? observation?.snapshot : nil,
            validate: { [weak self, weak tab] in
                guard let self, let tab else { return false }
                return self.permits(tab, capability: capability)
                    && (capability == .read || self.onScreen(tab))
            }
        )
        return await PageAutomationGuard.$current.withValue(scope) {
            guard scope.validate(), webURL(of: tab) == url else { return failure("Page access changed. Read the page again.") }
            return await PageDriver.$expectedObservation.withValue(usesRef ? observation?.snapshot : nil) {
                var capturedImage: Data?
                let output: String
                if name == "screenshotPage" {
                    capturedImage = await PageDriver.screenshot(in: view)
                    output =
                        capturedImage == nil
                        ? "Screenshot unavailable; use readPage for redacted text."
                        : "Screenshot captured.\n" + (await PageDriver.snapshot(view, viewportOnly: true))
                } else {
                    output = await pageAction(name: name, arguments: arguments, view: view)
                }
                guard scope.validate(), !Task.isCancelled else {
                    observations[tab.id] = nil
                    return failure("Page access changed before the operation finished. Its contents were not returned.")
                }
                let prefixes = [
                    "PAGE TEXT:", "Clicked", "Typed", "Selected", "Scrolled", "Already at", "Went back.",
                    "CONTROL:", "Condition met.", "Set checked", "Checked state", "Screenshot captured.", "Dispatched hover", "Sent ",
                ]
                let filledCount = arguments["fields"]?.arrayValue?.count ?? 0
                let succeeded =
                    prefixes.contains { output.hasPrefix($0) } || (name == "fillFields" && output.hasPrefix("Filled \(filledCount) of \(filledCount) fields."))
                var content: [String: Value] = ["tabID": .string(tab.id.uuidString), "content": .string(AgentToolkit.untrusted(output))]
                if let current = PageDriver.observation(in: view), current.url == webURL(of: tab)?.absoluteString,
                    output.contains("observationID: " + current.id) {
                    observations[tab.id] = PageObservation(id: current.id, snapshot: current.id, documentURL: current.url)
                    content["observationID"] = .string(current.id)
                    if PageOutputBudget.cost(current.url) <= 512 { content["url"] = .string(current.url) }
                } else {
                    observations[tab.id] = nil
                }
                hasReadContent = true
                destinations.formUnion(PageDriver.listedLinks(in: output).map { destinationKey($0.url) })
                let value: Value = .object(content)
                var blocks: [MCP.Tool.Content] = [.text(text: encoded(value), annotations: nil, _meta: nil)]
                if let capturedImage { blocks.append(.image(data: capturedImage.base64EncodedString(), mimeType: "image/jpeg", annotations: nil, _meta: nil)) }
                return CallTool.Result(content: blocks, structuredContent: Optional.some(value), isError: !succeeded)
            }
        }
    }

    private func pageAction(name: String, arguments: [String: Value], view: WKWebView) async -> String {
        let ref = arguments["ref"]?.intValue ?? 0
        switch name {
        case "readPage":
            return await PageDriver.readRenderedPage(
                view, lookingFor: arguments["lookingFor"]?.stringValue ?? "", textOffset: arguments["textOffset"]?.intValue ?? 0,
                controlOffset: arguments["controlOffset"]?.intValue ?? 0,
                scope: arguments["scope"]?.stringValue ?? "", viewportOnly: arguments["viewportOnly"]?.boolValue ?? false)
        case "clickOnPage":
            return await PageDriver.click(ref: ref, label: "", in: view, announced: true)
        case "typeOnPage":
            return await PageDriver.type(
                text: arguments["text"]?.stringValue ?? "", intoField: "", ref: ref, submit: arguments["submit"]?.boolValue ?? false, in: view, announced: true)
        case "selectOption":
            return await PageDriver.selectOption(arguments["option"]?.stringValue ?? "", ref: ref, field: "", in: view, announced: true)
        case "scrollPage":
            return await PageDriver.scroll(direction: arguments["direction"]?.stringValue ?? "", ref: ref, in: view)
        case "hoverOnPage":
            return await PageDriver.hover(ref: ref, in: view)
        case "pressKey":
            return await PageDriver.pressKey(arguments["key"]?.stringValue ?? "", ref: ref, in: view)
        case "fillFields":
            let fields =
                arguments["fields"]?.arrayValue?.compactMap { value -> PageDriver.FieldValue? in
                    guard case .object(let field) = value, let ref = field["ref"]?.intValue,
                        let value = field["value"]?.stringValue, let select = field["select"]?.boolValue
                    else { return nil }
                    return .init(ref: ref, value: value, select: select)
                } ?? []
            return await PageDriver.fillFields(fields, in: view, announced: true)
        case "inspectControl":
            return await PageDriver.inspectControl(ref: ref, offset: arguments["offset"]?.intValue ?? 0, in: view)
        case "setChecked":
            return await PageDriver.setChecked(ref: ref, checked: arguments["checked"]?.boolValue ?? false, in: view, announced: true)
        case "waitForPage":
            return await PageDriver.waitForPage(
                condition: arguments["condition"]?.stringValue ?? "", value: arguments["value"]?.stringValue ?? "",
                timeout: arguments["timeout"]?.intValue ?? 5, in: view)
        case "goBack":
            return await PageDriver.goBack(in: view)
        default:
            return "Unknown page action."
        }
    }

    private func navigate(_ raw: String, tab: BrowserTab, grant: Grant) async -> CallTool.Result {
        guard let url = permittedDestination(raw) else {
            return failure("Use an HTTP(S) URL observed in a page link, or ask the user to open and share the page.")
        }
        let previousURL = webURL(of: tab)
        let origin = SitePermissions.origin(for: url)
        if origin != grant.origin {
            guard await openConsent(clientName, url) else { return failure("Navigation was not approved.") }
        }
        guard permits(tab, capability: .control), onScreen(tab), webURL(of: tab) == previousURL else {
            return failure("Page access changed before navigation.")
        }
        guard browser.sitePermissions.assistantAccess(for: origin) != .deny else { return failure("Assistant access is off for this website.") }
        observations[tab.id] = nil
        grants[tab.id] = Grant(origin: origin, access: grant.access)
        tab.load(url, transition: .agent)
        return success("Navigation started. Use readPage after the page loads. Redirects to a different website require new sharing.")
    }

    private func openNewTab(_ raw: String) async -> CallTool.Result {
        guard grants.keys.contains(where: { sharedTab($0).map { permits($0, capability: .control) } ?? false }),
            let url = permittedDestination(raw)
        else { return failure("Opening a tab requires control access and an allowed HTTP(S) URL.") }
        guard await openConsent(clientName, url), isConnected, available(), !Task.isCancelled else {
            return failure("Opening the page was not approved.")
        }
        guard browser.sitePermissions.assistantAccess(for: SitePermissions.origin(for: url)) != .deny else {
            return failure("Assistant access is off for this website.")
        }
        let tab = browser.newTab(url: url, transition: .agent)
        grants[tab.id] = Grant(origin: SitePermissions.origin(for: url), access: .control)
        return success("Opened tab \(tab.id.uuidString). Use readPage after it loads.")
    }

    private func permittedDestination(_ raw: String) -> URL? {
        guard let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            url.host() != nil, url.user == nil, url.password == nil,
            !hasReadContent || destinations.contains(destinationKey(url))
        else { return nil }
        return url
    }

    private func destinationKey(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.url?.absoluteString ?? url.absoluteString
    }

    private func sharedTab(_ id: UUID) -> BrowserTab? {
        guard isConnected, available(), !Task.isCancelled,
            let grant = grants[id], let tab = browser.tabs.first(where: { $0.id == id }),
            !tab.isPrivate, !tab.isClosed, let url = webURL(of: tab),
            SitePermissions.origin(for: url) == grant.origin
        else { return nil }
        tab.assistantAccess.pageChanged(url: url)
        return tab.assistantAccess.effectivePolicy == .deny ? nil : tab
    }

    private func permits(_ tab: BrowserTab, capability: AssistantPageCapability) -> Bool {
        guard sharedTab(tab.id) === tab, let grant = grants[tab.id] else { return false }
        if capability == .control {
            return grant.access == .control && tab.assistantAccess.effectivePolicy != .readOnly
        }
        return true
    }

    private func webURL(of tab: BrowserTab) -> URL? {
        guard !tab.isShowingSystemPage else { return nil }
        let url = tab.isMaterialised ? tab.webView.url : URL(string: tab.urlString)
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func onScreen(_ tab: BrowserTab) -> Bool {
        browser.activeTabID == tab.id || browser.splitPanes?.contains(where: { $0 === tab }) == true
    }

    private func encoded(_ value: Value) -> String {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func success(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private func failure(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
    }
}
