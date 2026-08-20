// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import WebKit

@Observable
final class BrowserSettings {
    #if DEBUG
    static let shared = BrowserSettings(defaults: StageMode.defaults)
    #else
    static let shared = BrowserSettings()
    #endif

    private enum Key {
        static let appearance = "appearance.mode"
        static let pageZoom = "content.defaultZoom"
        static let startup = "startup.behavior"
        static let newTab = "startup.newTab"
        static let homepage = "startup.homepage"
        static let searchEngine = "search.engine"
        static let customSearchName = "search.custom.name"
        static let customSearchTemplate = "search.custom.template"
        static let suggestions = "search.suggestions"
        static let agentOnlyInput = "search.agentOnly"
        static let historyRetention = "privacy.historyRetention"
        static let clearOnQuit = "privacy.clearOnQuit"
        static let certificateExceptions = "privacy.certificateExceptions"
        static let javaScript = "content.javaScript"
        static let blockPopups = "content.blockPopups"
        static let blockTrackers = "content.blockTrackers"
        static let autoplay = "content.autoplay"
        static let downloadFolder = "downloads.folder"
        static let askWhereToSave = "downloads.ask"
        static let userAgent = "advanced.userAgent"
        static let customUserAgent = "advanced.userAgent.custom"
        static let webInspector = "advanced.webInspector"
        static let reportIssueButton = "appearance.reportIssueButton"
        static let startPageOrder = "startPage.order"
        static let startPageHidden = "startPage.hidden"
        static let startPageHiddenSites = "startPage.hiddenSites"
    }

    static let sessionKeys: [String] = [
        Key.startup, Key.newTab, Key.homepage,
        Key.searchEngine, Key.customSearchName, Key.customSearchTemplate,
        Key.suggestions, Key.agentOnlyInput,
        Key.historyRetention, Key.clearOnQuit, Key.certificateExceptions,
        Key.javaScript, Key.blockPopups, Key.blockTrackers, Key.autoplay,
        Key.startPageOrder, Key.startPageHidden, Key.startPageHiddenSites,
    ]

    private static let sessionKeySet = Set(sessionKeys)

    @ObservationIgnored private let appDefaults: UserDefaults
    @ObservationIgnored private var sessionDefaults: UserDefaults

    @ObservationIgnored var onWebPreferencesChanged: (() -> Void)?

    private func store(for key: String) -> UserDefaults {
        Self.sessionKeySet.contains(key) ? sessionDefaults : appDefaults
    }

    private func write(_ value: Any?, forKey key: String) {
        store(for: key).set(value, forKey: key)
    }

    private func remove(_ key: String) {
        store(for: key).removeObject(forKey: key)
    }

    private func string(_ key: String) -> String? {
        store(for: key).string(forKey: key)
    }

    private func bool(_ key: String) -> Bool {
        store(for: key).bool(forKey: key)
    }

    private func object(_ key: String) -> Any? {
        store(for: key).object(forKey: key)
    }

    private func double(_ key: String) -> Double {
        store(for: key).double(forKey: key)
    }

    private func stringArray(_ key: String) -> [String]? {
        store(for: key).stringArray(forKey: key)
    }

    // MARK: - Appearance

    var appearance: AppearanceMode {
        didSet {
            guard appearance != oldValue else { return }
            write(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    var showsReportIssueButton: Bool {
        didSet {
            guard showsReportIssueButton != oldValue else { return }
            write(showsReportIssueButton, forKey: Key.reportIssueButton)
        }
    }

    var pageZoom: Double {
        didSet {
            guard pageZoom != oldValue else { return }
            write(pageZoom, forKey: Key.pageZoom)
            onWebPreferencesChanged?()
        }
    }

    // MARK: - Startup

    var startup: StartupBehavior {
        didSet { write(startup.rawValue, forKey: Key.startup) }
    }

    var newTab: NewTabBehavior {
        didSet { write(newTab.rawValue, forKey: Key.newTab) }
    }

    var homepage: String {
        didSet { write(homepage, forKey: Key.homepage) }
    }

    var homepageURL: URL? {
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    var newTabURL: URL? {
        switch newTab {
        case .startPage, .blank:
            nil
        case .homepage:
            homepageURL
        }
    }

    // MARK: - Search

    var searchEngineID: String {
        didSet { write(searchEngineID, forKey: Key.searchEngine) }
    }

    var customSearchName: String {
        didSet { write(customSearchName, forKey: Key.customSearchName) }
    }

    var customSearchTemplate: String {
        didSet { write(customSearchTemplate, forKey: Key.customSearchTemplate) }
    }

    var searchEngine: SearchEngine {
        if searchEngineID == SearchEngine.customID {
            return SearchEngine.custom(name: customSearchName, template: customSearchTemplate)
        }
        return SearchEngine.catalog.first { $0.id == searchEngineID } ?? SearchEngine.duckDuckGo
    }

    var showsSearchSuggestions: Bool {
        didSet { write(showsSearchSuggestions, forKey: Key.suggestions) }
    }

    var agentOnlyInput: Bool {
        didSet { write(agentOnlyInput, forKey: Key.agentOnlyInput) }
    }

    // MARK: - Privacy

    var historyRetention: HistoryRetention {
        didSet { write(historyRetention.rawValue, forKey: Key.historyRetention) }
    }

    var clearsDataOnQuit: Bool {
        didSet { write(clearsDataOnQuit, forKey: Key.clearOnQuit) }
    }

    var allowsCertificateExceptions: Bool {
        didSet {
            guard allowsCertificateExceptions != oldValue else { return }
            write(allowsCertificateExceptions, forKey: Key.certificateExceptions)
            if !allowsCertificateExceptions {
                CertificateTrust.forgetAll()
            }
        }
    }

    // MARK: - What pages may do

    var javaScriptEnabled: Bool {
        didSet {
            guard javaScriptEnabled != oldValue else { return }
            write(javaScriptEnabled, forKey: Key.javaScript)
            onWebPreferencesChanged?()
        }
    }

    var blocksPopups: Bool {
        didSet {
            guard blocksPopups != oldValue else { return }
            write(blocksPopups, forKey: Key.blockPopups)
            onWebPreferencesChanged?()
        }
    }

    var blocksTrackers: Bool {
        didSet {
            guard blocksTrackers != oldValue else { return }
            write(blocksTrackers, forKey: Key.blockTrackers)
            ContentBlocker.shared.refresh()
        }
    }

    var autoplay: AutoplayPolicy {
        didSet {
            guard autoplay != oldValue else { return }
            write(autoplay.rawValue, forKey: Key.autoplay)
            onWebPreferencesChanged?()
        }
    }

    // MARK: - Downloads

    var downloadFolder: URL {
        didSet { write(downloadFolder.path(percentEncoded: false), forKey: Key.downloadFolder) }
    }

    var asksWhereToSave: Bool {
        didSet { write(asksWhereToSave, forKey: Key.askWhereToSave) }
    }

    static var defaultDownloadFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Advanced

    var userAgentMode: UserAgentMode {
        didSet {
            guard userAgentMode != oldValue else { return }
            write(userAgentMode.rawValue, forKey: Key.userAgent)
            onWebPreferencesChanged?()
        }
    }

    var customUserAgent: String {
        didSet {
            write(customUserAgent, forKey: Key.customUserAgent)
            if userAgentMode == .custom {
                onWebPreferencesChanged?()
            }
        }
    }

    var userAgentString: String? {
        switch userAgentMode {
        case .safari:
            WebViewPool.safariUserAgent
        case .linen:
            "\(WebViewPool.safariUserAgent) Linen/\(UpdateFeed.currentVersion)"
        case .custom:
            customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? WebViewPool.safariUserAgent
                : customUserAgent
        }
    }

    var webInspectorEnabled: Bool {
        didSet {
            guard webInspectorEnabled != oldValue else { return }
            write(webInspectorEnabled, forKey: Key.webInspector)
            onWebPreferencesChanged?()
        }
    }

    // MARK: - Start page

    var startPageOrder: [StartPageSection] {
        didSet {
            guard startPageOrder != oldValue else { return }
            write(startPageOrder.map(\.rawValue), forKey: Key.startPageOrder)
        }
    }

    private var hiddenStartPageSections: Set<StartPageSection> {
        didSet {
            guard hiddenStartPageSections != oldValue else { return }
            write(hiddenStartPageSections.map(\.rawValue), forKey: Key.startPageHidden)
        }
    }

    func showsStartPageSection(_ section: StartPageSection) -> Bool {
        !hiddenStartPageSections.contains(section)
    }

    subscript(showsStartPageSection section: StartPageSection) -> Bool {
        get { showsStartPageSection(section) }
        set { setStartPageSection(section, shown: newValue) }
    }

    func setStartPageSection(_ section: StartPageSection, shown: Bool) {
        if shown {
            hiddenStartPageSections.remove(section)
        } else {
            hiddenStartPageSections.insert(section)
        }
    }

    private(set) var hiddenFrequentHosts: Set<String> = [] {
        didSet {
            guard hiddenFrequentHosts != oldValue else { return }
            write(Array(hiddenFrequentHosts), forKey: Key.startPageHiddenSites)
        }
    }

    func hideFrequentSite(host: String) {
        hiddenFrequentHosts.insert(host.lowercased())
    }

    func restoreHiddenFrequentSites() {
        hiddenFrequentHosts = []
    }

    func moveStartPageSections(from source: IndexSet, to destination: Int) {
        let moved = source.map { startPageOrder[$0] }
        var order = startPageOrder
        for index in source.sorted(by: >) {
            order.remove(at: index)
        }
        let insertion = destination - source.count(where: { $0 < destination })
        order.insert(contentsOf: moved, at: min(max(insertion, 0), order.count))
        startPageOrder = order
    }

    private static func resolveOrder(_ stored: [String]?) -> [StartPageSection] {
        let known = stored?.compactMap(StartPageSection.init(rawValue:)) ?? []
        var order = known
        for section in StartPageSection.allCases where !order.contains(section) {
            order.append(section)
        }
        return order
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard, sessionDefaults: UserDefaults? = nil) {
        let session = sessionDefaults ?? defaults
        self.appDefaults = defaults
        self.sessionDefaults = session

        func pick(_ key: String) -> UserDefaults {
            Self.sessionKeySet.contains(key) ? session : defaults
        }
        func string(_ key: String) -> String? {
            pick(key).string(forKey: key)
        }
        func bool(_ key: String) -> Bool {
            pick(key).bool(forKey: key)
        }
        func object(_ key: String) -> Any? {
            pick(key).object(forKey: key)
        }
        func double(_ key: String) -> Double {
            pick(key).double(forKey: key)
        }
        func stringArray(_ key: String) -> [String]? {
            pick(key).stringArray(forKey: key)
        }

        appearance = string(Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        showsReportIssueButton = object(Key.reportIssueButton) as? Bool ?? true
        #if DEBUG
        if StageMode.isActive {
            showsReportIssueButton = false
        }
        #endif
        let storedZoom = double(Key.pageZoom)
        pageZoom = storedZoom > 0 ? storedZoom : 1

        startup = string(Key.startup)
            .flatMap(StartupBehavior.init(rawValue:)) ?? .restore
        self.newTab = string(Key.newTab)
            .flatMap(NewTabBehavior.init(rawValue:)) ?? .startPage
        homepage = string(Key.homepage) ?? ""

        searchEngineID = string(Key.searchEngine) ?? SearchEngine.duckDuckGo.id
        customSearchName = string(Key.customSearchName) ?? ""
        customSearchTemplate = string(Key.customSearchTemplate) ?? ""
        showsSearchSuggestions = object(Key.suggestions) as? Bool ?? true
        agentOnlyInput = bool(Key.agentOnlyInput)

        historyRetention = string(Key.historyRetention)
            .flatMap(HistoryRetention.init(rawValue:)) ?? .forever
        clearsDataOnQuit = bool(Key.clearOnQuit)
        allowsCertificateExceptions = bool(Key.certificateExceptions)

        javaScriptEnabled = object(Key.javaScript) as? Bool ?? true
        blocksPopups = object(Key.blockPopups) as? Bool ?? true
        blocksTrackers = object(Key.blockTrackers) as? Bool ?? true
        autoplay = string(Key.autoplay)
            .flatMap(AutoplayPolicy.init(rawValue:)) ?? .allow

        let storedFolder = string(Key.downloadFolder)
        downloadFolder = storedFolder.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? Self.defaultDownloadFolder
        asksWhereToSave = bool(Key.askWhereToSave)

        userAgentMode = string(Key.userAgent)
            .flatMap(UserAgentMode.init(rawValue:)) ?? .safari
        customUserAgent = string(Key.customUserAgent) ?? ""
        webInspectorEnabled = object(Key.webInspector) as? Bool ?? true

        startPageOrder = Self.resolveOrder(stringArray(Key.startPageOrder))
        hiddenStartPageSections = Set(
            (stringArray(Key.startPageHidden) ?? [])
                .compactMap(StartPageSection.init(rawValue:))
        )
        hiddenFrequentHosts = Set(stringArray(Key.startPageHiddenSites) ?? [])
    }

    func useSessionDefaults(_ defaults: UserDefaults) {
        guard defaults !== sessionDefaults else { return }
        sessionDefaults = defaults

        startup = string(Key.startup).flatMap(StartupBehavior.init(rawValue:)) ?? .restore
        newTab = string(Key.newTab).flatMap(NewTabBehavior.init(rawValue:)) ?? .startPage
        homepage = string(Key.homepage) ?? ""

        searchEngineID = string(Key.searchEngine) ?? SearchEngine.duckDuckGo.id
        customSearchName = string(Key.customSearchName) ?? ""
        customSearchTemplate = string(Key.customSearchTemplate) ?? ""
        showsSearchSuggestions = object(Key.suggestions) as? Bool ?? true
        agentOnlyInput = bool(Key.agentOnlyInput)

        historyRetention = string(Key.historyRetention).flatMap(HistoryRetention.init(rawValue:)) ?? .forever
        clearsDataOnQuit = bool(Key.clearOnQuit)
        allowsCertificateExceptions = bool(Key.certificateExceptions)

        javaScriptEnabled = object(Key.javaScript) as? Bool ?? true
        blocksPopups = object(Key.blockPopups) as? Bool ?? true
        blocksTrackers = object(Key.blockTrackers) as? Bool ?? true
        autoplay = string(Key.autoplay).flatMap(AutoplayPolicy.init(rawValue:)) ?? .allow

        startPageOrder = Self.resolveOrder(stringArray(Key.startPageOrder))
        hiddenStartPageSections = Set(
            (stringArray(Key.startPageHidden) ?? []).compactMap(StartPageSection.init(rawValue:))
        )
        hiddenFrequentHosts = Set(stringArray(Key.startPageHiddenSites) ?? [])

        onWebPreferencesChanged?()
    }

    // MARK: - Applying

    var forcesDarkAppearance = false {
        didSet {
            guard forcesDarkAppearance != oldValue else { return }
            applyAppearance()
        }
    }

    func applyAppearance() {
        NSApp.appearance = forcesDarkAppearance
            ? NSAppearance(named: .darkAqua)
            : appearance.nsAppearance
    }

    func apply(to configuration: WKWebViewConfiguration) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = javaScriptEnabled
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !blocksPopups
        configuration.mediaTypesRequiringUserActionForPlayback = autoplay.mediaTypes
        configuration.preferences.isElementFullscreenEnabled = true
        // `isInspectable` only lets an external inspector attach. This private
        // preference enables the page's own Inspect Element item.
        configuration.preferences.setValue(webInspectorEnabled, forKey: "developerExtrasEnabled")
    }

    func apply(to webView: WKWebView) {
        apply(to: webView.configuration)
        if webView.pageZoom != pageZoom {
            webView.pageZoom = pageZoom
        }
        webView.customUserAgent = userAgentString
        webView.isInspectable = webInspectorEnabled
    }

    func resetToDefaults() {
        appearance = .system
        pageZoom = 1
        startup = .restore
        newTab = .startPage
        homepage = ""
        searchEngineID = SearchEngine.duckDuckGo.id
        customSearchName = ""
        customSearchTemplate = ""
        showsSearchSuggestions = true
        agentOnlyInput = false
        historyRetention = .forever
        clearsDataOnQuit = false
        allowsCertificateExceptions = false
        javaScriptEnabled = true
        blocksPopups = true
        blocksTrackers = true
        autoplay = .allow
        downloadFolder = Self.defaultDownloadFolder
        asksWhereToSave = false
        userAgentMode = .safari
        customUserAgent = ""
        webInspectorEnabled = true
        startPageOrder = StartPageSection.allCases
        hiddenStartPageSections = []
        hiddenFrequentHosts = []
        onWebPreferencesChanged?()
    }
}

// MARK: - Choices

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

enum StartupBehavior: String, CaseIterable, Identifiable {
    case restore
    case newTab

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .restore:
            "Previous tabs"
        case .newTab:
            "A new tab"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .restore:
            "Restores the tabs from your last session, in the same order."
        case .newTab:
            "Opens one new tab. Previous tabs aren’t restored."
        }
    }
}

enum StartPageSection: String, CaseIterable, Identifiable {
    case recentTasks
    case frequentSites
    case history
    case downloads

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .recentTasks:
            "Recent Tasks"
        case .frequentSites:
            "Frequently Visited"
        case .history:
            "History"
        case .downloads:
            "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .recentTasks:
            "clock.arrow.circlepath"
        case .frequentSites:
            "chart.bar"
        case .history:
            "clock"
        case .downloads:
            "arrow.down"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .recentTasks:
            "Repeat a recent task"
        case .frequentSites:
            "Websites you visit most"
        case .history:
            "Recently visited pages"
        case .downloads:
            "Recent files"
        }
    }
}

enum NewTabBehavior: String, CaseIterable, Identifiable {
    case startPage
    case blank
    case homepage

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .startPage:
            "Start page"
        case .blank:
            "Blank"
        case .homepage:
            "Homepage"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .startPage:
            "The websites you visit most, your recent requests, and your downloads."
        case .blank:
            "A blank page, with the address bar ready."
        case .homepage:
            "A website you choose."
        }
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case forever

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .day:
            "A day"
        case .week:
            "A week"
        case .month:
            "A month"
        case .year:
            "A year"
        case .forever:
            "Forever"
        }
    }

    var maximumAge: TimeInterval? {
        switch self {
        case .day:
            86_400
        case .week:
            7 * 86_400
        case .month:
            30 * 86_400
        case .year:
            365 * 86_400
        case .forever:
            nil
        }
    }
}

enum AutoplayPolicy: String, CaseIterable, Identifiable {
    case allow
    case silent
    case block

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .allow:
            "Allow"
        case .silent:
            "Muted"
        case .block:
            "Never"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .allow:
            "Video and audio may start playing as soon as a page loads."
        case .silent:
            "Video plays without sound until you click."
        case .block:
            "Nothing plays until you press play."
        }
    }

    var mediaTypes: WKAudiovisualMediaTypes {
        switch self {
        case .allow:
            []
        case .silent:
            .audio
        case .block:
            .all
        }
    }
}

enum UserAgentMode: String, CaseIterable, Identifiable {
    case safari
    case linen = "Linen"
    case custom

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .safari:
            "Safari"
        case .linen:
            "Linen"
        case .custom:
            "Custom"
        }
    }
}

// MARK: - Search engines

nonisolated struct SearchEngine: Identifiable, Hashable, Sendable {
    enum SuggestionFormat: Hashable {
        case phrases
        case openSearch
    }

    static let customID = "custom"

    let id: String
    let name: String
    let template: String
    let suggestTemplate: String?
    let suggestionFormat: SuggestionFormat
    init(
        id: String,
        name: String,
        template: String,
        suggestTemplate: String? = nil,
        suggestionFormat: SuggestionFormat = .openSearch
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.suggestTemplate = suggestTemplate
        self.suggestionFormat = suggestionFormat
    }

    var isCustom: Bool {
        id == Self.customID
    }

    var host: String? {
        URLComponents(string: template.replacingOccurrences(of: "%s", with: "q"))?.host
    }

    func searchURL(for query: String) -> URL? {
        Self.expand(template, with: query)
    }

    func suggestURL(for query: String) -> URL? {
        guard let suggestTemplate else { return nil }
        return Self.expand(suggestTemplate, with: query)
    }

    private static func expand(_ template: String, with query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }

        let filled = template.contains("%s")
            ? template.replacingOccurrences(of: "%s", with: escaped)
            : template.trimmingCharacters(in: .whitespaces) + escaped

        guard let url = URL(string: filled),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host()?.contains(".") == true
        else { return nil }
        return url
    }

    static func custom(name: String, template: String) -> SearchEngine {
        SearchEngine(
            id: customID,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom" : name,
            template: template
        )
    }

    // MARK: - The list

    static let duckDuckGo = SearchEngine(
        id: "duckduckgo",
        name: "DuckDuckGo",
        template: "https://duckduckgo.com/?q=%s",
        suggestTemplate: "https://duckduckgo.com/ac/?q=%s&kl=wt-wt",
        suggestionFormat: .phrases
    )

    static let catalog: [SearchEngine] = [
        duckDuckGo,
        SearchEngine(
            id: "google",
            name: "Google",
            template: "https://www.google.com/search?q=%s",
            suggestTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        ),
        SearchEngine(
            id: "bing",
            name: "Bing",
            template: "https://www.bing.com/search?q=%s",
            suggestTemplate: "https://api.bing.com/osjson.aspx?query=%s"
        ),
        SearchEngine(
            id: "brave",
            name: "Brave Search",
            template: "https://search.brave.com/search?q=%s",
            suggestTemplate: "https://search.brave.com/api/suggest?q=%s"
        ),
        SearchEngine(
            id: "startpage",
            name: "Startpage",
            template: "https://www.startpage.com/sp/search?query=%s"
        ),
        SearchEngine(
            id: "ecosia",
            name: "Ecosia",
            template: "https://www.ecosia.org/search?q=%s"
        ),
        SearchEngine(
            id: "kagi",
            name: "Kagi",
            template: "https://kagi.com/search?q=%s"
        ),
        SearchEngine(
            id: "wikipedia",
            name: "Wikipedia",
            template: "https://en.wikipedia.org/w/index.php?search=%s"
        ),
    ]
}
