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

    private static let liveSettings = NSHashTable<BrowserSettings>.weakObjects()
    @ObservationIgnored private var isReceivingAppSetting = false

    private enum Key {
        static let appearance = "appearance.mode"
        static let websiteTint = "appearance.websiteTint"
        static let websiteColor = "appearance.websiteColor"
        static let loomStyle = "appearance.loomStyle"
        static let transparency = "appearance.transparency"
        static let pageZoom = "content.defaultZoom"
        static let sleepsInactiveTabs = "tabs.sleep"
        static let archiveTabsAfter = "tabs.archive"
        static let linkPreview = "content.linkPreview"
        static let fullAddress = "content.fullAddress"
        static let linkPeek = "content.linkPeek"
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
        static let mediaPlayer = "media.player"
        static let lyrics = "media.lyrics"
        static let github = "sidePanel.github"
        static let tabColorRefraction = "appearance.tabColorRefraction"
        static let solidSidePanel = "appearance.solidSidePanel"
        static let minimal = "appearance.minimal"
        static let minimalBar = "appearance.minimalBar"
        static let minimalBarAutoHide = "appearance.minimalBarAutoHide"
        static let automaticPiP = "media.automaticPiP"
        static let videoInPlayer = "experiments.videoInPlayer"
        static let passwordAutofill = "autofill.passwords"
        static let passwordExtension = "autofill.passwordExtension"
        static let contactAutofill = "autofill.contacts"
        static let paymentCardAutofill = "privacy.paymentCardAutofill"
        static let downloadFolder = "downloads.folder"
        static let askWhereToSave = "downloads.ask"
        static let downloadRetention = "downloads.retention"
        static let userAgent = "advanced.userAgent"
        static let customUserAgent = "advanced.userAgent.custom"
        static let webInspector = "advanced.webInspector"
        static let updateChannel = "updates.channel"
        static let startPageOrder = "startPage.order"
        static let startPageHidden = "startPage.hidden"
        static let startPageHiddenSites = "startPage.hiddenSites"
        static let translationTarget = "translation.target"
        static let alwaysTranslate = "translation.always"
    }

    static let sessionKeys: [String] = [
        Key.searchEngine, Key.customSearchName, Key.customSearchTemplate,
        Key.suggestions, Key.agentOnlyInput,
        Key.historyRetention, Key.clearOnQuit, Key.certificateExceptions,
        Key.paymentCardAutofill, Key.contactAutofill, Key.passwordAutofill, Key.passwordExtension,
        Key.javaScript, Key.blockPopups, Key.blockTrackers, Key.autoplay,
        Key.startPageOrder, Key.startPageHidden, Key.startPageHiddenSites,
    ]

    @ObservationIgnored private let store: SettingsDefaults

    @ObservationIgnored var onContentBlockingChanged: (() -> Void)?
    @ObservationIgnored var onWebPreferencesChanged: (() -> Void)?
    @ObservationIgnored var onUpdateChannelChanged: ((UpdateChannel) -> Void)?
    @ObservationIgnored var onLyricsChanged: ((Bool) -> Void)?
    @ObservationIgnored var onGitHubChanged: ((Bool) -> Void)?
    @ObservationIgnored var onMediaPlayerChanged: ((Bool) -> Void)?
    @ObservationIgnored var onAutomaticPictureInPictureChanged: ((Bool) -> Void)?
    @ObservationIgnored var onVideoInPlayerChanged: ((Bool) -> Void)?
    @ObservationIgnored var onArchiveTabsAfterChanged: ((TabArchiveDelay) -> Void)?

    private func write(_ value: Any?, forKey key: String) {
        guard !isReceivingAppSetting else { return }
        store.set(value, forKey: key)
        guard !store.isSessionKey(key) else { return }
        for other in Self.liveSettings.allObjects where other !== self && other.store.app === store.app {
            other.receiveAppSetting(key, from: self)
        }
    }

    private func receiveAppSetting(_ key: String, from source: BrowserSettings) {
        isReceivingAppSetting = true
        defer { isReceivingAppSetting = false }
        switch key {
        case Key.appearance:
            appearance = source.appearance
        case Key.loomStyle:
            loomStyle = source.loomStyle
        case Key.websiteTint:
            matchesWebsiteColor = source.matchesWebsiteColor
        case Key.transparency:
            transparency = source.transparency
        case Key.linkPreview:
            showsLinkPreview = source.showsLinkPreview
        case Key.fullAddress:
            showsFullAddress = source.showsFullAddress
        case Key.linkPeek:
            peeksAtLinks = source.peeksAtLinks
        case Key.mediaPlayer:
            showsMediaPlayer = source.showsMediaPlayer
        case Key.lyrics:
            showsLyrics = source.showsLyrics
        case Key.github:
            showsGitHub = source.showsGitHub
        case Key.tabColorRefraction:
            refractsTabColor = source.refractsTabColor
        case Key.solidSidePanel:
            hasSolidSidePanel = source.hasSolidSidePanel
        case Key.minimal:
            isMinimal = source.isMinimal
        case Key.minimalBar:
            minimalBarEdge = source.minimalBarEdge
        case Key.minimalBarAutoHide:
            hidesMinimalBar = source.hidesMinimalBar
        case Key.automaticPiP:
            automaticPictureInPicture = source.automaticPictureInPicture
        case Key.videoInPlayer:
            showsVideoInPlayer = source.showsVideoInPlayer
        default:
            receiveWebAppSetting(key, from: source)
        }
    }

    private func receiveWebAppSetting(_ key: String, from source: BrowserSettings) {
        switch key {
        case Key.pageZoom:
            pageZoom = source.pageZoom
        case Key.sleepsInactiveTabs:
            sleepsInactiveTabs = source.sleepsInactiveTabs
        case Key.archiveTabsAfter:
            archiveTabsAfter = source.archiveTabsAfter
        case Key.downloadFolder:
            downloadFolder = source.downloadFolder
        case Key.askWhereToSave:
            asksWhereToSave = source.asksWhereToSave
        case Key.downloadRetention:
            downloadRetention = source.downloadRetention
        case Key.userAgent:
            userAgentMode = source.userAgentMode
        case Key.customUserAgent:
            customUserAgent = source.customUserAgent
        case Key.webInspector:
            webInspectorEnabled = source.webInspectorEnabled
        case Key.updateChannel:
            updateChannel = source.updateChannel
        case Key.translationTarget:
            translationTargetID = source.translationTargetID
        case Key.alwaysTranslate:
            alwaysTranslatedLanguages = source.alwaysTranslatedLanguages
        default:
            break
        }
    }

    // MARK: - Appearance

    var appearance: AppearanceMode {
        didSet {
            guard appearance != oldValue else { return }
            write(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    var loomStyle: LoomStyle {
        didSet {
            guard loomStyle != oldValue else { return }
            write(loomStyle.rawValue, forKey: Key.loomStyle)
        }
    }

    var transparency: Double {
        didSet {
            guard transparency != oldValue else { return }
            write(transparency, forKey: Key.transparency)
        }
    }

    var matchesWebsiteColor: Bool {
        didSet {
            guard matchesWebsiteColor != oldValue else { return }
            write(matchesWebsiteColor, forKey: Key.websiteTint)
        }
    }

    var updateChannel: UpdateChannel {
        didSet {
            guard updateChannel != oldValue else { return }
            write(updateChannel.rawValue, forKey: Key.updateChannel)
            onUpdateChannelChanged?(updateChannel)
        }
    }

    var pageZoom: Double {
        didSet {
            guard pageZoom != oldValue else { return }
            write(pageZoom, forKey: Key.pageZoom)
            onWebPreferencesChanged?()
        }
    }

    // MARK: - Media

    var showsMediaPlayer: Bool {
        didSet {
            guard showsMediaPlayer != oldValue else { return }
            write(showsMediaPlayer, forKey: Key.mediaPlayer)
            onMediaPlayerChanged?(showsMediaPlayer)
        }
    }

    var showsLyrics: Bool {
        didSet {
            guard showsLyrics != oldValue else { return }
            write(showsLyrics, forKey: Key.lyrics)
            onLyricsChanged?(showsLyrics)
        }
    }

    var showsGitHub: Bool {
        didSet {
            guard showsGitHub != oldValue else { return }
            write(showsGitHub, forKey: Key.github)
            onGitHubChanged?(showsGitHub)
        }
    }

    var sleepsInactiveTabs: Bool {
        didSet {
            guard sleepsInactiveTabs != oldValue else { return }
            write(sleepsInactiveTabs, forKey: Key.sleepsInactiveTabs)
        }
    }

    var archiveTabsAfter: TabArchiveDelay {
        didSet {
            guard archiveTabsAfter != oldValue else { return }
            write(archiveTabsAfter.rawValue, forKey: Key.archiveTabsAfter)
            onArchiveTabsAfterChanged?(archiveTabsAfter)
        }
    }

    var isMinimal: Bool {
        didSet {
            guard isMinimal != oldValue else { return }
            write(isMinimal, forKey: Key.minimal)
        }
    }

    var minimalBarEdge: MinimalBarEdge {
        didSet {
            guard minimalBarEdge != oldValue else { return }
            write(minimalBarEdge.rawValue, forKey: Key.minimalBar)
        }
    }

    var hidesMinimalBar: Bool {
        didSet {
            guard hidesMinimalBar != oldValue else { return }
            write(hidesMinimalBar, forKey: Key.minimalBarAutoHide)
        }
    }

    var showsLinkPreview: Bool {
        didSet {
            guard showsLinkPreview != oldValue else { return }
            write(showsLinkPreview, forKey: Key.linkPreview)
        }
    }

    var showsFullAddress: Bool {
        didSet {
            guard showsFullAddress != oldValue else { return }
            write(showsFullAddress, forKey: Key.fullAddress)
        }
    }

    var peeksAtLinks: Bool {
        didSet {
            guard peeksAtLinks != oldValue else { return }
            write(peeksAtLinks, forKey: Key.linkPeek)
        }
    }

    var refractsTabColor: Bool {
        didSet {
            guard refractsTabColor != oldValue else { return }
            write(refractsTabColor, forKey: Key.tabColorRefraction)
        }
    }

    var hasSolidSidePanel: Bool {
        didSet {
            guard hasSolidSidePanel != oldValue else { return }
            write(hasSolidSidePanel, forKey: Key.solidSidePanel)
        }
    }

    var automaticPictureInPicture: Bool {
        didSet {
            guard automaticPictureInPicture != oldValue else { return }
            write(automaticPictureInPicture, forKey: Key.automaticPiP)
            onAutomaticPictureInPictureChanged?(automaticPictureInPicture)
        }
    }

    // MARK: - Experiments

    var showsVideoInPlayer: Bool {
        didSet {
            guard showsVideoInPlayer != oldValue else { return }
            write(showsVideoInPlayer, forKey: Key.videoInPlayer)
            if showsVideoInPlayer {
                automaticPictureInPicture = false
            }
            onVideoInPlayerChanged?(showsVideoInPlayer)
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
            onContentBlockingChanged?()
        }
    }

    var autoplay: AutoplayPolicy {
        didSet {
            guard autoplay != oldValue else { return }
            write(autoplay.rawValue, forKey: Key.autoplay)
            onWebPreferencesChanged?()
        }
    }

    var fillsPasswords: Bool {
        didSet {
            write(fillsPasswords, forKey: Key.passwordAutofill)
            PasswordAutofill.shared.refreshPolicy()
        }
    }

    var passwordExtensionID: String {
        didSet {
            write(passwordExtensionID, forKey: Key.passwordExtension)
            PasswordAutofill.shared.refreshPolicy()
        }
    }

    var fillsContacts: Bool {
        didSet {
            write(fillsContacts, forKey: Key.contactAutofill)
            AutofillSaveCoordinator.shared.refreshPolicy()
        }
    }

    var fillsPaymentCards: Bool {
        didSet {
            write(fillsPaymentCards, forKey: Key.paymentCardAutofill)
            AutofillSaveCoordinator.shared.refreshPolicy()
        }
    }

    // MARK: - Downloads

    var downloadFolder: URL {
        didSet { write(downloadFolder.path(percentEncoded: false), forKey: Key.downloadFolder) }
    }

    var asksWhereToSave: Bool {
        didSet { write(asksWhereToSave, forKey: Key.askWhereToSave) }
    }

    var downloadRetention: DownloadRetention {
        didSet { write(downloadRetention.rawValue, forKey: Key.downloadRetention) }
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

    // MARK: - Translation

    var translationTargetID: String {
        didSet {
            guard translationTargetID != oldValue else { return }
            write(translationTargetID.isEmpty ? nil : translationTargetID, forKey: Key.translationTarget)
        }
    }

    var translationTarget: Locale.Language {
        get {
            translationTargetID.isEmpty
                ? TranslationLanguage.preferred
                : Locale.Language(identifier: translationTargetID)
        }
        set { translationTargetID = TranslationLanguage.key(newValue) }
    }

    private(set) var alwaysTranslatedLanguages: Set<String> = [] {
        didSet {
            guard alwaysTranslatedLanguages != oldValue else { return }
            write(alwaysTranslatedLanguages.sorted(), forKey: Key.alwaysTranslate)
        }
    }

    func alwaysTranslates(_ language: Locale.Language) -> Bool {
        alwaysTranslatedLanguages.contains(TranslationLanguage.key(language))
    }

    func setAlwaysTranslates(_ always: Bool, _ language: Locale.Language) {
        let key = TranslationLanguage.key(language)
        if always {
            alwaysTranslatedLanguages.insert(key)
        } else {
            alwaysTranslatedLanguages.remove(key)
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
            let following = StartPageSection.allCases
                .drop { $0 != section }
                .dropFirst()
                .first { order.contains($0) }
            if let following, let index = order.firstIndex(of: following) {
                order.insert(section, at: index)
            } else {
                order.append(section)
            }
        }
        return order
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard, sessionDefaults: UserDefaults? = nil) {
        let store = SettingsDefaults(
            app: defaults,
            session: sessionDefaults ?? defaults,
            sessionKeys: Set(Self.sessionKeys)
        )
        self.store = store

        appearance = store.string(Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        let storedLoomStyle = store.string(Key.loomStyle)
        loomStyle = storedLoomStyle == LoomStyle.transparent.rawValue ? .transparent : .standard
        if let storedWebsiteTint = store.object(Key.websiteTint) as? Bool {
            matchesWebsiteColor = storedWebsiteTint
        } else if storedLoomStyle == "websiteTint" {
            matchesWebsiteColor = true
        } else if storedLoomStyle == nil {
            matchesWebsiteColor = store.object(Key.websiteColor) as? Bool ?? true
        } else {
            matchesWebsiteColor = false
        }
        transparency = store.object(Key.transparency) == nil
            ? 0.5
            : min(max(store.double(Key.transparency), 0), 1)
        showsMediaPlayer = store.object(Key.mediaPlayer) as? Bool ?? true
        showsLyrics = store.object(Key.lyrics) as? Bool ?? false
        showsGitHub = store.object(Key.github) as? Bool ?? false
        refractsTabColor = store.object(Key.tabColorRefraction) as? Bool ?? true
        hasSolidSidePanel = store.object(Key.solidSidePanel) as? Bool ?? false
        isMinimal = store.object(Key.minimal) as? Bool ?? false
        minimalBarEdge = store.string(Key.minimalBar).flatMap(MinimalBarEdge.init(rawValue:)) ?? .bottom
        hidesMinimalBar = store.object(Key.minimalBarAutoHide) as? Bool ?? false
        sleepsInactiveTabs = store.object(Key.sleepsInactiveTabs) as? Bool ?? false
        archiveTabsAfter = store.string(Key.archiveTabsAfter)
            .flatMap(TabArchiveDelay.init(rawValue:)) ?? .never
        showsLinkPreview = store.object(Key.linkPreview) as? Bool ?? true
        showsFullAddress = store.object(Key.fullAddress) as? Bool ?? false
        peeksAtLinks = store.object(Key.linkPeek) as? Bool ?? true
        automaticPictureInPicture = store.object(Key.automaticPiP) as? Bool ?? false
        showsVideoInPlayer = store.object(Key.videoInPlayer) as? Bool ?? false
        fillsPasswords = store.object(Key.passwordAutofill) as? Bool ?? true
        passwordExtensionID = store.object(Key.passwordExtension) as? String ?? ""
        fillsContacts = store.object(Key.contactAutofill) as? Bool ?? true
        fillsPaymentCards = store.object(Key.paymentCardAutofill) as? Bool ?? true
        updateChannel = store.string(Key.updateChannel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .release
        let storedZoom = store.double(Key.pageZoom)
        pageZoom = storedZoom > 0 ? storedZoom : 1

        searchEngineID = store.string(Key.searchEngine) ?? SearchEngine.duckDuckGo.id
        customSearchName = store.string(Key.customSearchName) ?? ""
        customSearchTemplate = store.string(Key.customSearchTemplate) ?? ""
        showsSearchSuggestions = store.object(Key.suggestions) as? Bool ?? true
        agentOnlyInput = store.bool(Key.agentOnlyInput)

        historyRetention = store.string(Key.historyRetention)
            .flatMap(HistoryRetention.init(rawValue:)) ?? .forever
        clearsDataOnQuit = store.bool(Key.clearOnQuit)
        allowsCertificateExceptions = store.bool(Key.certificateExceptions)

        javaScriptEnabled = store.object(Key.javaScript) as? Bool ?? true
        blocksPopups = store.object(Key.blockPopups) as? Bool ?? true
        blocksTrackers = store.object(Key.blockTrackers) as? Bool ?? true
        autoplay = store.string(Key.autoplay)
            .flatMap(AutoplayPolicy.init(rawValue:)) ?? .allow

        let storedFolder = store.string(Key.downloadFolder)
        downloadFolder = storedFolder.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? Self.defaultDownloadFolder
        asksWhereToSave = store.bool(Key.askWhereToSave)
        downloadRetention = store.string(Key.downloadRetention)
            .flatMap(DownloadRetention.init(rawValue:)) ?? .manually

        userAgentMode = store.string(Key.userAgent)
            .flatMap(UserAgentMode.init(rawValue:)) ?? .safari
        customUserAgent = store.string(Key.customUserAgent) ?? ""
        webInspectorEnabled = store.object(Key.webInspector) as? Bool ?? true
        translationTargetID = store.string(Key.translationTarget) ?? ""
        alwaysTranslatedLanguages = Set(store.stringArray(Key.alwaysTranslate) ?? [])

        startPageOrder = Self.resolveOrder(store.stringArray(Key.startPageOrder))
        hiddenStartPageSections = Set(
            (store.stringArray(Key.startPageHidden) ?? [])
                .compactMap(StartPageSection.init(rawValue:))
        )
        hiddenFrequentHosts = Set(store.stringArray(Key.startPageHiddenSites) ?? [])

        if store.object(Key.websiteTint) == nil {
            write(matchesWebsiteColor, forKey: Key.websiteTint)
        }
        Self.liveSettings.add(self)
    }

    func useSessionDefaults(_ defaults: UserDefaults) {
        guard store.useSession(defaults) else { return }
        fillsPasswords = store.object(Key.passwordAutofill) as? Bool ?? true
        passwordExtensionID = store.object(Key.passwordExtension) as? String ?? ""
        fillsContacts = store.object(Key.contactAutofill) as? Bool ?? true
        fillsPaymentCards = store.object(Key.paymentCardAutofill) as? Bool ?? true

        searchEngineID = store.string(Key.searchEngine) ?? SearchEngine.duckDuckGo.id
        customSearchName = store.string(Key.customSearchName) ?? ""
        customSearchTemplate = store.string(Key.customSearchTemplate) ?? ""
        showsSearchSuggestions = store.object(Key.suggestions) as? Bool ?? true
        agentOnlyInput = store.bool(Key.agentOnlyInput)

        historyRetention = store.string(Key.historyRetention).flatMap(HistoryRetention.init(rawValue:)) ?? .forever
        clearsDataOnQuit = store.bool(Key.clearOnQuit)
        allowsCertificateExceptions = store.bool(Key.certificateExceptions)

        javaScriptEnabled = store.object(Key.javaScript) as? Bool ?? true
        blocksPopups = store.object(Key.blockPopups) as? Bool ?? true
        blocksTrackers = store.object(Key.blockTrackers) as? Bool ?? true
        autoplay = store.string(Key.autoplay).flatMap(AutoplayPolicy.init(rawValue:)) ?? .allow

        startPageOrder = Self.resolveOrder(store.stringArray(Key.startPageOrder))
        hiddenStartPageSections = Set(
            (store.stringArray(Key.startPageHidden) ?? []).compactMap(StartPageSection.init(rawValue:))
        )
        hiddenFrequentHosts = Set(store.stringArray(Key.startPageHiddenSites) ?? [])

        onWebPreferencesChanged?()
    }

    // MARK: - Applying

    var forcesDarkAppearance = false {
        didSet {
            guard forcesDarkAppearance != oldValue else { return }
            applyAppearance()
        }
    }

    @ObservationIgnored var onAppearanceChanged: (() -> Void)?

    func applyAppearance() {
        onAppearanceChanged?()
    }

    func apply(to configuration: WKWebViewConfiguration) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = javaScriptEnabled
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !blocksPopups
        configuration.mediaTypesRequiringUserActionForPlayback = javaScriptEnabled ? [] : autoplay.mediaTypes
        configuration.preferences.isElementFullscreenEnabled = true
        // `isInspectable` only lets an external inspector attach. This private
        // preference enables the page's own Inspect Element item.
        configuration.preferences.setValue(webInspectorEnabled, forKey: "developerExtrasEnabled")
        WebKitFeatures.apply(to: configuration.preferences)
        NativeApplePay.apply(to: configuration.preferences)
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
        fillsPasswords = true
        passwordExtensionID = ""
        fillsContacts = true
        fillsPaymentCards = true
        appearance = .system
        loomStyle = .standard
        matchesWebsiteColor = true
        transparency = 0.5
        refractsTabColor = true
        hasSolidSidePanel = false
        pageZoom = 1
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
        translationTargetID = ""
        alwaysTranslatedLanguages = []
        startPageOrder = StartPageSection.allCases
        hiddenStartPageSections = []
        hiddenFrequentHosts = []
        onWebPreferencesChanged?()
    }
}
