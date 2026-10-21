// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

enum BrowserSettingsKey {
    static let appearance = "appearance.mode"
    static let websiteTint = "appearance.websiteTint"
    static let websiteColor = "appearance.websiteColor"
    static let loomStyle = "appearance.loomStyle"
    static let transparency = "appearance.transparency"
    static let pageZoom = "content.defaultZoom"
    static let tabSleep = "tabs.sleep"
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
    static let developerHosts = "advanced.developerHosts"
    static let nonDeveloperHosts = "advanced.nonDeveloperHosts"
    static let updateChannel = "updates.channel"
    static let startPageOrder = "startPage.order"
    static let startPageHidden = "startPage.hidden"
    static let startPageHiddenSites = "startPage.hiddenSites"
    static let translationTarget = "translation.target"
    static let alwaysTranslate = "translation.always"

    static let session: [String] = [
        searchEngine, customSearchName, customSearchTemplate,
        suggestions, agentOnlyInput,
        historyRetention, clearOnQuit, certificateExceptions,
        paymentCardAutofill, contactAutofill, passwordAutofill, passwordExtension,
        javaScript, blockPopups, blockTrackers, autoplay,
        startPageOrder, startPageHidden, startPageHiddenSites,
    ]
}
