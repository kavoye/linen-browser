// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SettingsEntry: Identifiable, Hashable {
    let id: String
    let category: SettingsCategory
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let keywords: [String]

    init(
        _ id: String,
        _ category: SettingsCategory,
        _ title: LocalizedStringResource,
        _ detail: LocalizedStringResource,
        _ keywords: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.keywords = keywords
    }

    var searchableTitle: String {
        String(localized: title)
    }
    var searchableDetail: String {
        String(localized: detail)
    }

    var targetAnchor: String {
        id == "appearance.transparency" ? "appearance.windowStyle" : id
    }

    static func == (lhs: SettingsEntry, rhs: SettingsEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SettingsIndex {
    private static let toolKeywords = AgentToolCatalog.all
        .filter(\.isConfigurable)
        .flatMap { [String(localized: $0.title).lowercased(), String(localized: $0.summary).lowercased()] }

    private enum Rank: Int {
        case titlePrefix = 0
        case titleWord = 1
        case titleContains = 2
        case detail = 3
        case keyword = 4
    }

    static let all: [SettingsEntry] = [
        SettingsEntry("autofill.contacts", .autofill, "Contacts and addresses",
                      "Save and fill contact details.",
                      ["contact", "address", "email", "phone", "name", "shipping", "billing", "autofill",
                       "save suggestions", "reset prompts"]),
        SettingsEntry("autofill.passwords", .autofill, "Passwords",
                      "Save and fill website logins.",
                      ["password", "passkey", "icloud", "login", "autofill", "save suggestions", "reset prompts"]),
        SettingsEntry("autofill.cards", .autofill, "Payment cards", "Save and fill cards at checkout.",
                      ["autofill", "credit", "debit", "card", "wallet", "payment", "save suggestions", "reset prompts"]),
        SettingsEntry("autofill.applePay", .autofill, "Apple Pay", "Scan a code to pay with iPhone.",
                      ["apple pay", "payment", "wallet", "touch id", "checkout"]),
        SettingsEntry("general.sleepTabs", .general, "Sleep inactive tabs",
                      "When your Mac runs low on memory, inactive tabs unload. They reload when you open them.",
                      ["sleep", "sleeping", "discard", "unload", "memory", "ram", "background tabs", "reload"]),
        SettingsEntry("general.linkPreview", .general, "Show link address",
                      "Show a link's address at the bottom of the page when you point at it.",
                      ["link", "preview", "status bar", "hover", "url", "address", "capsule", "destination"]),
        SettingsEntry("general.mediaPlayer", .general, "Show media player",
                      "Pause or skip audio and video playing in any tab.",
                      ["media", "player", "video", "audio", "dock", "sidebar", "picture in picture", "pip", "now playing"]),
        SettingsEntry("general.automaticPiP", .general, "Automatic Picture in Picture",
                      "Video keeps playing in a floating window when you leave its tab.",
                      ["picture in picture", "pip", "automatic", "auto", "float", "floating", "video",
                       "pop out", "always on top", "media", "player", "overlay",
                       ]),
        SettingsEntry("general.lyrics", .general, "Show lyrics",
                      "Send the song and artist to LRCLIB to find lyrics. Private tabs don't send song details.",
                      ["lyrics", "words", "sing", "karaoke", "music", "song", "lrclib", "synced", "media", "player"]),
        SettingsEntry("general.agentOnly", .search, "Always ask the assistant", "Send questions to the assistant. Open links normally.",
                      ["agent", "assistant", "ask", "search", "no search", "web search", "address bar",
                       "omnibox", "command palette", "start page", "model", "llm", "chat",
                       "ask instead of search", "ai", "always ask",
                       ]),
        SettingsEntry("experiments.videoInPlayer", .experiments, "Show video in the player",
                      "Video from a tab you leave moves into the sidebar player.",
                      ["experiment", "experimental", "video", "player", "media", "sidebar", "picture",
                       "borrow", "flag",
                       ]),
        SettingsEntry("general.import", .general, "Bookmarks",
                      "Import an HTML file from Safari, Chrome, Firefox, or Edge.",
                      ["import", "bookmarks", "favourites", "favorites", "html", "file", "safari",
                       "chrome", "google", "firefox", "edge", "arc", "brave", "opera", "vivaldi",
                       "migrate", "switch", "transfer",
                      ]),
        SettingsEntry("search.engine", .search, "Search engine", "Used when you or the assistant search the web.",
                      ["search engine", "google", "duckduckgo", "bing", "brave", "kagi", "ecosia", "startpage", "wikipedia"]),
        SettingsEntry("search.custom", .search, "Search URL", "Use %s where the search term goes.",
                      ["custom", "own", "template", "url", "%s"]),
        SettingsEntry("search.suggestions", .search, "Search suggestions", "Suggestions from your search engine as you type.",
                      ["autocomplete", "suggest", "predictions", "typing", "omnibox", "address bar"]),
        SettingsEntry("general.defaultBrowser", .general, "Open links from other apps", "Whether Linen is your default browser.",
                      ["default browser", "default", "links", "handler", "http", "https", "system"]),

        SettingsEntry("appearance.theme", .appearance, "Theme", "Light, dark, or match your Mac.",
                      ["dark mode", "light mode", "theme", "appearance", "colour", "color", "night"]),
        SettingsEntry("appearance.windowStyle", .appearance, "Window style", "Choose Standard or Transparent.",
                      ["loom", "window", "standard", "liquid glass", "clear", "opacity",
                       "transparency", "transparent", "translucent", "contrast", "toolbar",
                       "sidebar", "chrome",
                      ]),
        SettingsEntry("appearance.transparency", .appearance, "Transparency",
                      "Move left for more transparency or right for more contrast. Available with Transparent window style.",
                      ["opacity", "glass", "translucent", "contrast", "window style"]),
        SettingsEntry("appearance.websiteTint", .appearance, "Website tint",
                      "Use the current website's color in the toolbar and sidebar.",
                      ["website", "colour", "color", "tint", "favicon", "toolbar", "sidebar", "chrome",
                      ]),
        SettingsEntry("appearance.zoom", .appearance, "Page zoom", "Set the default zoom for websites. You can also zoom individual tabs.",
                      ["zoom", "text size", "font size", "magnify", "bigger", "smaller", "scale"]),
        SettingsEntry("appearance.sidebar", .appearance, "Show sidebar", "Show or hide the list of tabs.",
                      ["sidebar", "tabs", "tab list", "column", "hide"]),
        SettingsEntry("appearance.refraction", .appearance, "Tint selected tab", "Color the selected tab using the website icon.",
                      ["refract", "glass", "colour", "color", "tint", "selected tab", "favicon", "sidebar"]),
        SettingsEntry("appearance.sidebarStyle", .appearance, "Icons only", "Narrow the sidebar to its icons.",
                      ["sidebar", "icons", "narrow", "compact", "tabs"]),

        SettingsEntry("profiles.current", .profiles, "Current profile", "Edit the current profile.",
                      ["profile", "current", "open now", "name", "color", "symbol"]),
        SettingsEntry("profiles.list", .profiles, "Profiles", "Edit or switch profiles.",
                      ["profile", "profiles", "work", "personal", "switch", "rename", "delete", "symbol",
                       "icon", "colour", "color", "grey", "gray", "tint", "order", "reorder", "drag",
                       "clear history",
                       ]),
        SettingsEntry("profiles.add", .profiles, "Add profile…", "A new profile starts with no history, tabs, or sign-ins.",
                      ["profile", "new profile", "add", "create", "second", "another", "work", "school"]),
        SettingsEntry("profiles.launch", .profiles, "Open profile", "Choose which profile opens when Linen starts.",
                      ["launch", "startup", "start up", "open", "default profile", "boot"]),

        SettingsEntry("privacy.clear", .privacy, "Clear browsing data", "Choose a time range to clear history, cookies, and cached files.",
                      ["cookies", "cache", "reset", "storage", "site data", "delete", "erase", "wipe",
                       "local storage", "clear", "history", "time range", "last hour",
                       ]),
        SettingsEntry("privacy.trackers", .privacy, "Block known trackers", "Block trackers on every website.",
                      ["tracker", "trackers", "ads", "advertising", "analytics", "block", "privacy",
                       "content blocker", "adblock", "ad blocker", "telemetry", "pixel",
                       ]),
        SettingsEntry("privacy.storage", .privacy, "Website data", "How many websites store data on this Mac.",
                      ["cookies", "storage", "sites", "local storage", "data"]),
        SettingsEntry("privacy.history", .privacy, "Keep history for", "How long visited pages are kept.",
                      ["history", "retention", "forget", "expire", "keep"]),
        SettingsEntry("privacy.quit", .privacy, "Clear on quit", "Clear cookies, site data, and cached files when you quit Linen.",
                      ["quit", "exit", "private", "automatic", "cookies", "cache"]),
        SettingsEntry("privacy.assistant", .provider, "Allowed without asking", "Websites the assistant may act on without asking.",
                      ["agent", "assistant", "permission", "always allow", "consent", "purchase", "checkout",
                       "payment", "delete", "post", "revoke", "grant", "confirm", "ask",
                       ]),

        SettingsEntry("websites.javascript", .websites, "JavaScript", "Turn scripts off for every website.",
                      ["javascript", "js", "scripts", "disable"]),
        SettingsEntry("websites.popups", .websites, "Block pop-ups", "Stop windows a website opens on its own.",
                      ["popup", "pop up", "block", "ads", "windows"]),
        SettingsEntry("websites.autoplay", .websites, "Autoplay", "Whether video and sound may start on their own.",
                      ["autoplay", "video", "sound", "audio", "media", "mute"]),
        SettingsEntry("websites.permissions", .websites, "Permissions", "Which websites may use your location, camera, microphone, and notifications.",
                      ["permission", "location", "camera", "microphone", "mic", "notifications", "geolocation",
                       "gps", "webcam", "video call", "allow", "deny", "revoke", "getusermedia",
                       ]),
        SettingsEntry("websites.list", .websites, "Websites you've changed", "View websites with custom settings.",
                      ["site settings", "per site", "exceptions", "assistant access", "read only", "control",
                       "keep active", "keep awake", "always active", "always loaded", "memory", "unload", "background",
                       "trackers", "tracker exception", "reset website",
                       ]),

        SettingsEntry("downloads.folder", .downloads, "Save files to", "Where downloaded files are saved.",
                      ["downloads", "folder", "location", "directory", "save", "files"]),
        SettingsEntry("downloads.retention", .downloads, "Remove download list items",
                      "How long finished downloads stay in the list.",
                      ["downloads", "history", "list", "clear", "remove", "keep", "retention", "quit"]),
        SettingsEntry("downloads.ask", .downloads, "Ask where to save each file", "Choose a location every time.",
                      ["ask", "prompt", "where", "save as"]),
        SettingsEntry("downloads.list", .downloads, "Recent downloads", "View downloads and their saved locations.",
                      ["downloads", "files", "recent", "history"]),

        SettingsEntry("provider.model", .provider, "Model", "The model used by the assistant.",
                      ["gpt", "claude", "llama", "model id", "llm", "provider", "answers"]),
        SettingsEntry("provider.key", .provider, "API key", "Add or change the selected provider's API key.",
                      ["credential", "token", "secret", "keychain", "authentication"]),
        SettingsEntry("provider.endpoint", .provider, "Endpoint", "Edit a custom provider's server address.",
                      ["base url", "server", "custom provider", "remove endpoint"]),
        SettingsEntry("provider.thinking", .provider, "Thinking", "How much reasoning effort the model spends.",
                      ["reasoning", "effort", "thinking"]),
        SettingsEntry("provider.tools", .provider, "Tools", "What the assistant may do in the browser.",
                      ["tools", "skills", "abilities", "permissions", "search", "click", "type",
                       "read page", "tabs", "video", "context window",
                      ] + toolKeywords),
        SettingsEntry("provider.connected", .provider, "Providers",
                      "Every provider you've set up.",
                      ["api key", "token", "secret", "keychain", "openai", "anthropic", "google", "groq",
                       "mistral", "deepseek", "openrouter", "xai", "apple intelligence",
                       "base url", "endpoint", "custom", "ollama", "lm studio", "localhost", "server",
                       "add provider", "connect",
                      ]),
        SettingsEntry("assistant.linkPeek", .provider, "Summarize a link on hover",
                      "Hold Shift while pointing at a link to get a summary before opening it.",
                      ["link", "peek", "preview", "summary", "summarize", "hover", "shift",
                       "gist", "skim", "read ahead",
                      ]),
        SettingsEntry("assistant.pauseAfter", .provider, "Pause after",
                      "Set a model request limit for long assistant tasks.",
                      ["long tasks", "no limit", "100 requests", "250 requests", "500 requests",
                       "continue", "resume", "request limit"]),
        SettingsEntry("voice.readAloud", .provider, "Read aloud", "Speak answers as they arrive.",
                      ["speech", "speak", "mute", "voice", "aloud"]),
        SettingsEntry("voice.talk", .provider, "Push to talk", "Hold the shortcut to speak, then release it to send.",
                      ["shortcut", "hotkey", "microphone", "mic", "option key", "activation"]),
        SettingsEntry("openai.replyLength", .provider, "Reply length", "Choose short, medium, or long replies.",
                      ["verbosity", "response length", "openai"]),
        SettingsEntry("openai.voice", .provider, "Voice", "Choose voices for conversation and reading aloud.",
                      ["openai", "conversation voice", "speech", "dictation"]),
        SettingsEntry("openai.voice.speakingStyle", .provider, "Speaking style", "Set how the assistant speaks in conversations.",
                      ["openai", "voice instructions", "speak slowly"]),
        SettingsEntry("openai.voice.readingVoice", .provider, "Reading voice", "Choose the voice used to read replies aloud.",
                      ["openai", "text to speech", "read aloud"]),
        SettingsEntry("openai.voice.readingSpeed", .provider, "Reading speed", "Set the speed for reading replies aloud.",
                      ["openai", "speech rate", "read aloud"]),
        SettingsEntry("openai.connections", .provider, "Connections", "Connect MCP services your assistant can use.",
                      ["openai", "mcp", "tools", "service", "oauth", "sign in"]),
        SettingsEntry("openai.privacy", .provider, "Data and privacy", "Choose whether you can retrieve replies through the OpenAI API.",
                      ["openai", "keep replies", "store responses", "account", "retention"]),
        SettingsEntry("openai.developer", .provider, "Developer settings", "Configure hosted commands, voice models, and API JSON.",
                      ["openai", "shell", "hosted tools", "parameters"]),
        SettingsEntry("openai.developer.runCommands", .provider, "Run commands at OpenAI",
                      "Allow a hosted shell to run commands and create files.",
                      ["openai", "shell", "hosted commands", "code interpreter"]),
        SettingsEntry("openai.developer.voiceModels", .provider, "Voice models",
                      "Override models used for dictation, read aloud, and conversation.",
                      ["openai", "transcription model", "speech model", "conversation model"]),
        SettingsEntry("openai.developer.apiJSON", .provider, "API JSON",
                      "Edit additional response parameters and hosted tool definitions.",
                      ["openai", "json", "parameters", "hosted tools"]),
        SettingsEntry("extensions.installed", .extensions, "Web extensions", "Chrome extensions and Firefox add-ons running in Linen.",
                      ["installed extensions", "chrome", "web store", "firefox", "mozilla", "add-ons", "plugins", "adblock",
                       "safari extensions", "app store", "extension options", "remove extension", "check for updates"]),

        SettingsEntry("advanced.inspector", .advanced, "Web Inspector", "Add Inspect Element to a page's right-click menu.",
                      ["developer", "devtools", "inspector", "inspect", "debug", "console"]),
        SettingsEntry("advanced.mcp", .advanced, "External connections", "Connect an external assistant to tabs you choose.",
                      ["mcp", "external", "connection", "automation", "codex", "claude", "cursor", "client", "tools"]),
        SettingsEntry("advanced.features", .advanced, "Feature flags",
                      "Experimental WebKit features may break websites.",
                      ["webkit", "flags", "experimental", "features", "develop"]),
        SettingsEntry("advanced.certificates", .advanced, "Certificate exceptions", "Continue past a certificate macOS rejects. Linen forgets the exception when you quit.",
                      ["certificate", "ssl", "tls", "https", "self-signed", "proxy", "untrusted",
                       "invalid certificate", "exception", "warning",
                       ]),
        SettingsEntry("advanced.userAgent", .advanced, "User agent", "Changing this can break websites.",
                      ["user agent", "ua", "safari", "spoof", "identify"]),
        SettingsEntry("advanced.reset", .advanced, "Reset settings", "Put appearance, search, privacy, websites, and downloads back to their defaults.",
                      ["reset", "defaults", "factory", "start over"]),
        SettingsEntry("about.updates", .about, "Software update", "View the installed version and check for updates.",
                      ["update", "version", "release", "build", "upgrade"]),
        SettingsEntry("about.updates.channel", .about, "Update channel",
                      "Choose stable releases or preview builds.",
                      ["channel", "preview", "beta", "tip", "nightly", "early", "release",
                       "prerelease", "pre-release", "test build",
                       ]),
        SettingsEntry("about.report", .about, "Send feedback", "Opens a new issue on Linen's repository.",
                      ["report", "bug", "issue", "feedback", "github", "ladybug"]),
        SettingsEntry("about.acknowledgements", .about, "Acknowledgements", "Open source packages used by Linen.",
                      ["acknowledgements", "acknowledgments", "credits", "licence", "license", "open source",
                       "third party", "attribution", "notice", "sparkle", "mit", "apache",
                       ]),
    ]

    static let linkScheme = "linen-settings"

    static func link(to anchor: String) -> URL? {
        URL(string: "\(linkScheme)://\(anchor)")
    }

    static func caption(
        _ sentence: LocalizedStringResource,
        naming name: LocalizedStringResource,
        at anchor: String
    ) -> AttributedString {
        var text = AttributedString(String(localized: sentence))
        guard let range = text.range(of: String(localized: name)), let url = link(to: anchor) else {
            return text
        }
        text[range].link = url
        return text
    }

    static func search(_ raw: String) -> [SettingsEntry] {
        let needle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        return all
            .compactMap { entry -> (SettingsEntry, Rank)? in
                rank(entry, for: needle).map { (entry, $0) }
            }
            .sorted { left, right in
                left.1.rawValue == right.1.rawValue
                    ? left.0.searchableTitle.localizedStandardCompare(right.0.searchableTitle) == .orderedAscending
                    : left.1.rawValue < right.1.rawValue
            }
            .map(\.0)
    }

    private static func rank(_ entry: SettingsEntry, for needle: String) -> Rank? {
        let title = entry.searchableTitle.lowercased()
        if title.hasPrefix(needle) {
            return .titlePrefix
        }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
            return .titleWord
        }
        if title.contains(needle) {
            return .titleContains
        }
        if entry.keywords.contains(where: { $0.contains(needle) }) {
            return .keyword
        }
        if entry.searchableDetail.lowercased().contains(needle) {
            return .detail
        }
        return nil
    }
}

// MARK: - Anchors

extension EnvironmentValues {
    @Entry var settingsHighlight: String?
    @Entry var settingsIsCompact = false

    @Entry var settingsCardInset: CGFloat = 0

    @Entry var settingsSectionLit = false
}

extension View {
    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorModifier(anchor: anchor))
    }
}

private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String

    @Environment(\.settingsHighlight) private var highlight
    @Environment(\.settingsCardInset) private var cardInset
    @Environment(\.colorScheme) private var colorScheme

    private var isLit: Bool {
        highlight == anchor
    }

    private static let gap: CGFloat = 4

    private var isInCard: Bool {
        cardInset > 0
    }

    func body(content: Content) -> some View {
        content
            .background(alignment: .center) {
                if isInCard {
                    RoundedRectangle(cornerRadius: Theme.Radius.card - Self.gap, style: .continuous)
                        .fill(isLit ? Theme.Wash.hover : .clear)
                        .padding(.horizontal, -(cardInset - Self.gap))
                        .padding(.vertical, Self.gap - SettingsMetrics.cardInsetV)
                }
            }
            .environment(\.settingsSectionLit, isInCard ? false : isLit)
            .id(anchor)
            .animation(.easeOut(duration: 0.28), value: isLit)
    }
}
